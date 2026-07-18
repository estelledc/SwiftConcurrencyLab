import XCTest

@testable import SwiftConcurrencyCore

private actor ConcurrencyProbe {
  private var current = 0
  private var maximum = 0
  func enter() {
    current += 1
    maximum = max(maximum, current)
  }
  func leave() { current -= 1 }
  func maxObserved() -> Int { maximum }
}

final class SwiftConcurrencyCoreTests: XCTestCase {
  func testBoundedMapPreservesInputOrder() async throws {
    let values = try await boundedMap([3, 1, 2], limit: 2) { value in
      try await Task.sleep(for: .milliseconds(value))
      return value * 2
    }
    XCTAssertEqual(values, [6, 2, 4])
  }
  func testBoundedMapNeverExceedsLimit() async throws {
    let probe = ConcurrencyProbe()
    let values = try await boundedMap(Array(0..<12), limit: 3) { value in
      await probe.enter()
      try await Task.sleep(for: .milliseconds(3))
      await probe.leave()
      return value
    }
    let maximum = await probe.maxObserved()
    XCTAssertEqual(values, Array(0..<12))
    XCTAssertEqual(maximum, 3)
  }
  func testActorSerializesUnreadWrites() async {
    let counter = UnreadCounter()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 { group.addTask { await counter.increment() } }
    }
    let count = await counter.snapshot()
    XCTAssertEqual(count, 100)
  }
  func testUnsafeActorReentrancyAcceptsBothFromTheStaleCheck() async {
    let gate = AsyncGate()
    let quota = PinQuota(remaining: 1)
    async let first = quota.unsafePin(using: gate)
    async let second = quota.unsafePin(using: gate)
    await gate.waitUntilWaiters(2)
    await gate.open()
    let decisions = await [first, second]
    let remaining = await quota.snapshot()
    XCTAssertEqual(decisions.filter { $0 }.count, 2)
    XCTAssertEqual(remaining, -1)
  }
  func testReservationPreventsActorReentrancyOverdraft() async {
    let gate = AsyncGate()
    let quota = PinQuota(remaining: 1)
    async let first = quota.reservedPin(using: gate)
    async let second = quota.reservedPin(using: gate)
    await gate.waitUntilWaiters(1)
    await gate.open()
    let decisions = await [first, second]
    let remaining = await quota.snapshot()
    XCTAssertEqual(decisions.filter { $0 }.count, 1)
    XCTAssertEqual(remaining, 0)
  }
  func testActorReentrancyRunnerExposesDeterministicNegativeAndPositiveControls() async {
    let unsafe = await LabEngine().run(
      scenario: .actorReentrancy,
      strategy: .structured,
      actorReentrancyMode: .unsafe
    )
    XCTAssertEqual(unsafe.values, ["accepted=2", "remaining=-1"])

    let reserved = await LabEngine().run(
      scenario: .actorReentrancy,
      strategy: .structured,
      actorReentrancyMode: .reserved
    )
    XCTAssertEqual(reserved.values, ["accepted=1", "remaining=0"])
  }
  func testCellReuseProbeCancelsOldTaskAndRejectsItsLateCommit() async {
    let result = await runCellReuseProbe()
    XCTAssertTrue(result.cancellationRequested)
    XCTAssertEqual(result.committedID, "message-new")
    XCTAssertEqual(result.rejectedID, "message-old")
    XCTAssertEqual(
      result.events,
      [
        "configure=message-old",
        "cancel=message-old",
        "configure=message-new",
        "commit=message-new",
        "reject=message-old",
      ]
    )
  }
  func testCellReuseRunnerReturnsRuntimeEvidenceInsteadOfAStaticFixture() async {
    let engine = LabEngine()
    let outcome = await engine.run(scenario: .cellReuse, strategy: .structured)
    XCTAssertEqual(
      outcome.values,
      ["committed=message-new", "rejected=message-old", "cancelled=true"]
    )
    let events = await engine.recorder.events().filter { $0.runID == outcome.runID }
    XCTAssertEqual(events.map(\.phase), [.started, .scheduled, .cancelled, .warning, .completed])
    XCTAssertTrue(events.contains { $0.message == "stale commit message-old rejected" })
  }
  func testLegacyBridgeReturnsOnce() async throws {
    let value = try await LegacyCallbackAPI.loadAsync()
    XCTAssertEqual(value, "legacy-result")
  }
  func testLatestWinsKeepsNewestQuery() async {
    for _ in 0..<10 {
      let engine = LabEngine()
      let outcome = await engine.run(scenario: .latestWinsSearch, strategy: .structured)
      XCTAssertEqual(outcome.values, ["swift-result"])
    }
  }
  func testEveryScenarioHasAnAvailableStrategy() {
    XCTAssertTrue(LabScenario.allCases.allSatisfy { !$0.supportedStrategies.isEmpty })
  }

  func testEveryScenarioPointsToRealSourceAndOneShortXcodeAction() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    for scenario in LabScenario.allCases {
      let sourceURL = root.appendingPathComponent(scenario.sourceFile)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: sourceURL.path),
        "\(scenario.id) source file is missing: \(scenario.sourceFile)"
      )
      let source = try String(contentsOf: sourceURL, encoding: .utf8)
      XCTAssertTrue(
        source.contains(scenario.sourceAnchor),
        "\(scenario.id) source anchor is missing: \(scenario.sourceAnchor)"
      )
      XCTAssertFalse(scenario.xcodeAction.isEmpty)
      XCTAssertLessThanOrEqual(
        scenario.xcodeAction.count,
        80,
        "\(scenario.id) Xcode cue should stay compact"
      )
      XCTAssertTrue(
        scenario.documentationPath.hasPrefix("docs/lab-guide.md#lab-"),
        "\(scenario.id) should point to its detailed documentation card"
      )
    }
  }

  func testParallelStrategiesReturnStableComparableValues() async {
    let expected = ["profile", "messages", "recommendations"]
    for strategy in ConcurrencyStrategy.allCases {
      let engine = LabEngine()
      for _ in 0..<5 {
        let outcome = await engine.run(scenario: .parallelInbox, strategy: strategy)
        XCTAssertEqual(
          outcome.values, expected, "\(strategy.rawValue) should commit in input order")
      }
    }
  }
  func testStructuredParallelRecordsEvidencePhases() async {
    let engine = LabEngine()
    let outcome = await engine.run(scenario: .parallelInbox, strategy: .structured)
    let phases = await engine.recorder.events()
      .filter { $0.runID == outcome.runID }
      .map(\.phase)
    XCTAssertEqual(phases, [.started, .scheduled, .scheduled, .scheduled, .completed])
  }
  func testRecorderResetClearsEventsAndRestartsIDs() async {
    let recorder = LabEventRecorder()
    let runID = UUID()
    await recorder.record(
      runID: runID, strategy: .structured, scenario: .parallelInbox, phase: .started, "before reset"
    )
    await recorder.reset()
    await recorder.record(
      runID: runID, strategy: .structured, scenario: .parallelInbox, phase: .started, "after reset")
    let events = await recorder.events()
    XCTAssertEqual(events.map(\.id), [1])
    XCTAssertEqual(events.map(\.message), ["after reset"])
  }
  func testUnsupportedStrategyIsRejectedWithWarning() async {
    let engine = LabEngine()
    let outcome = await engine.run(scenario: .latestWinsSearch, strategy: .gcd)
    let events = await engine.recorder.events()
    XCTAssertTrue(outcome.summary.contains("尚未实现"))
    XCTAssertEqual(events.map(\.phase), [.warning])
  }
}
