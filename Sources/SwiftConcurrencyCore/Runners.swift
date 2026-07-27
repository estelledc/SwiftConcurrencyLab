import Foundation

private func event(
  _ recorder: LabEventRecorder, _ generation: Int, _ runID: UUID,
  _ strategy: ConcurrencyStrategy,
  _ scenario: LabScenario, _ phase: LabPhase, _ text: String
) async {
  await recorder.record(
    generation: generation, runID: runID, strategy: strategy, scenario: scenario, phase: phase,
    text)
}

private func completed(
  _ recorder: LabEventRecorder,
  _ generation: Int,
  _ runID: UUID,
  _ strategy: ConcurrencyStrategy,
  _ scenario: LabScenario,
  summary: String,
  values: [String] = []
) async -> LabOutcome {
  await event(recorder, generation, runID, strategy, scenario, .completed, summary)
  return LabOutcome(
    runID: runID, recorderGeneration: generation, summary: summary, values: values)
}

public enum BoundedPrefetchMode: String, CaseIterable, Sendable, Identifiable {
  case normal = "Normal"
  case cancellationProbe = "Cancellation Probe"

  public var id: String { rawValue }
}

public struct StructuredConcurrencyLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .structured
  private let service: SimulatedMailboxService
  private let actorReentrancyMode: ActorReentrancyMode
  private let boundedPrefetchMode: BoundedPrefetchMode
  public init(
    service: SimulatedMailboxService = .init(),
    actorReentrancyMode: ActorReentrancyMode = .reserved,
    boundedPrefetchMode: BoundedPrefetchMode = .normal
  ) {
    self.service = service
    self.actorReentrancyMode = actorReentrancyMode
    self.boundedPrefetchMode = boundedPrefetchMode
  }
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    let generation = await recorder.beginRun()
    await event(recorder, generation, runID, strategy, scenario, .started, "Task owner created")
    do {
      switch scenario {
      case .parallelInbox:
        for resource in ["profile", "messages", "recommendations"] {
          await event(
            recorder, generation, runID, strategy, scenario, .scheduled, "\(resource) scheduled")
        }
        async let profile = service.load("profile", delayMilliseconds: 40)
        async let messages = service.load("messages", delayMilliseconds: 15)
        async let recommendations = service.load("recommendations", delayMilliseconds: 25)
        let values = try await [profile, messages, recommendations]
        return await completed(
          recorder, generation, runID, strategy, scenario, summary: "3 个固定任务并发完成",
          values: values)
      case .cooperativeCancellation:
        for step in 1...6 {
          try Task.checkCancellation()
          _ = try await service.load("step-\(step)", delayMilliseconds: 25)
          await event(
            recorder, generation, runID, strategy, scenario, .suspended,
            "step \(step) resumed")
        }
        return await completed(
          recorder, generation, runID, strategy, scenario, summary: "所有取消检查点已通过")
      case .isolatedUnread:
        let counter = UnreadCounter()
        await withTaskGroup(of: Void.self) { group in
          for _ in 0..<20 { group.addTask { await counter.increment() } }
        }
        let count = await counter.snapshot()
        return await completed(
          recorder, generation, runID, strategy, scenario, summary: "actor 串行化共享写入",
          values: ["unread=\(count)"]
        )
      case .actorReentrancy:
        let gate = AsyncGate()
        let quota = PinQuota(remaining: 1)
        let decisions: [Bool]
        switch actorReentrancyMode {
        case .unsafe:
          async let first = quota.unsafePin(using: gate)
          async let second = quota.unsafePin(using: gate)
          await gate.waitUntilWaiters(2)
          await gate.open()
          decisions = await [first, second]
        case .reserved:
          async let first = quota.reservedPin(using: gate)
          async let second = quota.reservedPin(using: gate)
          await gate.waitUntilWaiters(1)
          await gate.open()
          decisions = await [first, second]
        }
        let accepted = decisions.filter { $0 }.count
        let remaining = await quota.snapshot()
        return await completed(
          recorder, generation, runID, strategy, scenario,
          summary:
            actorReentrancyMode == .unsafe
            ? "Unsafe 重用了 await 前的旧判断" : "Reservation 封住 await 缺口",
          values: ["accepted=\(accepted)", "remaining=\(remaining)"])
      case .latestWinsSearch:
        let store = LatestValueStore()
        await store.begin("swift")
        async let old: Void = {
          _ = try? await self.service.load("old", delayMilliseconds: 45, ignoreCancellation: true)
          await store.submit(query: "old", result: "old-result")
        }()
        async let latest: Void = {
          _ = try? await self.service.load("swift", delayMilliseconds: 10)
          await store.submit(query: "swift", result: "swift-result")
        }()
        _ = await (old, latest)
        return await completed(
          recorder, generation, runID, strategy, scenario,
          summary: "identity guard 保留最新查询",
          values: [await store.snapshot()])
      case .boundedPrefetch:
        switch boundedPrefetchMode {
        case .normal:
          await event(
            recorder, generation, runID, strategy, scenario, .scheduled,
            "12 previews scheduled with limit=4")
          let values = try await boundedMap(Array(1...12), limit: 4) { id in
            try await service.load("preview-\(id)", delayMilliseconds: UInt64(8 + id))
          }
          return await completed(
            recorder, generation, runID, strategy, scenario,
            summary: "TaskGroup 最多同时运行 4 个任务",
            values: values)
        case .cancellationProbe:
          await event(
            recorder, generation, runID, strategy, scenario, .scheduled,
            "4 previews suspended until parent cancellation")
          _ = try await boundedMap(Array(1...4), limit: 4) { _ in
            while true { try await Task.sleep(for: .seconds(3_600)) }
          }
          return await completed(
            recorder, generation, runID, strategy, scenario,
            summary: "Cancellation probe unexpectedly reached its timeout")
        }
      case .callbackBridge:
        let value = try await LegacyCallbackAPI.loadAsync()
        return await completed(
          recorder, generation, runID, strategy, scenario,
          summary: "checked continuation 恰好 resume 一次",
          values: [value])
      case .cellReuse:
        await event(
          recorder, generation, runID, strategy, scenario, .scheduled, "configure message-old")
        let result = await runCellReuseProbe()
        await event(
          recorder, generation, runID, strategy, scenario, .cancelled,
          "reuse cancelled message-old")
        await event(
          recorder, generation, runID, strategy, scenario, .warning,
          "stale commit message-old rejected")
        return await completed(
          recorder, generation, runID, strategy, scenario, summary: "复用链拒绝旧提交",
          values: [
            "committed=\(result.committedID ?? "none")",
            "rejected=\(result.rejectedID ?? "none")",
            "cancelled=\(result.cancellationRequested)",
          ])
      case .responsiveUI:
        await event(
          recorder, generation, runID, strategy, scenario, .scheduled, "background work scheduled")
        _ = try await service.load("CPU work moved outside MainActor", delayMilliseconds: 20)
        return await completed(
          recorder, generation, runID, strategy, scenario, summary: "等待时 Task 挂起，UI 可继续响应")
      }
    } catch is CancellationError {
      await event(
        recorder, generation, runID, strategy, scenario, .cancelled,
        "Task observed cancellation")
      return LabOutcome(
        runID: runID, recorderGeneration: generation, summary: "任务在协作式检查点取消")
    } catch {
      return LabOutcome(
        runID: runID, recorderGeneration: generation, summary: "unexpected error: \(error)")
    }
  }
}

public struct GCDLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .gcd
  public init() {}
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    let generation = await recorder.beginRun()
    await event(
      recorder, generation, runID, strategy, scenario, .started, "Dispatch work submitted")
    let resources = ["profile", "messages", "recommendations"]
    for resource in resources {
      await event(
        recorder, generation, runID, strategy, scenario, .scheduled, "\(resource) dispatched")
    }
    let values = await withTaskGroup(of: (Int, String).self, returning: [String].self) { group in
      for (index, value) in resources.enumerated() {
        let delay = [40, 15, 25][index]
        group.addTask {
          await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delay)) {
              continuation.resume(returning: (index, value))
            }
          }
        }
      }
      var output: [(Int, String)] = []
      for await value in group { output.append(value) }
      return output.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return await completed(
      recorder, generation, runID, strategy, scenario, summary: "Dispatch fan-out 完成，按输入顺序提交",
      values: values)
  }
}

public struct OperationLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .operation
  public init() {}
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    let generation = await recorder.beginRun()
    await event(
      recorder, generation, runID, strategy, scenario, .started, "OperationQueue created")
    let resources = ["profile", "messages", "recommendations"]
    for resource in resources {
      await event(
        recorder, generation, runID, strategy, scenario, .scheduled,
        "\(resource) operation enqueued")
    }
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 3
    let values = await withCheckedContinuation { continuation in
      let output = OperationAccumulator()
      for (index, value) in resources.enumerated() {
        queue.addOperation {
          Thread.sleep(forTimeInterval: [0.040, 0.015, 0.025][index])
          output.append(value, at: index)
        }
      }
      queue.addBarrierBlock { continuation.resume(returning: output.snapshot()) }
    }
    return await completed(
      recorder, generation, runID, strategy, scenario,
      summary: "OperationQueue fan-out 完成，按输入顺序提交",
      values: values)
  }
}

public struct LabEngine: Sendable {
  public let recorder: LabEventRecorder
  public init(recorder: LabEventRecorder = .init()) { self.recorder = recorder }
  public func run(
    scenario: LabScenario,
    strategy: ConcurrencyStrategy,
    actorReentrancyMode: ActorReentrancyMode = .reserved,
    boundedPrefetchMode: BoundedPrefetchMode = .normal
  ) async -> LabOutcome {
    guard scenario.supportedStrategies.contains(strategy) else {
      let runID = UUID()
      let generation = await recorder.beginRun()
      await recorder.record(
        generation: generation, runID: runID, strategy: strategy, scenario: scenario,
        phase: .warning,
        "Strategy is not implemented for this scenario")
      return LabOutcome(
        runID: runID, recorderGeneration: generation,
        summary: "\(strategy.rawValue) 尚未实现 \(scenario.title)")
    }
    switch strategy {
    case .gcd:
      return await GCDLabRunner().run(scenario, recorder: recorder)
    case .operation:
      return await OperationLabRunner().run(scenario, recorder: recorder)
    case .structured:
      return await StructuredConcurrencyLabRunner(
        actorReentrancyMode: actorReentrancyMode,
        boundedPrefetchMode: boundedPrefetchMode
      ).run(scenario, recorder: recorder)
    }
  }
}

public enum BoundedMapTerminal: Sendable, Equatable {
  case success
  case failure(errorType: String)
  case cancelled
}

public enum BoundedMapMonitorError: Error, Sendable, Equatable {
  case alreadyUsed
}

public struct BoundedMapMetrics: Sendable, Equatable {
  public let terminal: BoundedMapTerminal?
  public let terminalCount: Int
  public let startedCount: Int
  public let succeededCount: Int
  public let failedCount: Int
  public let cancelledCount: Int
  public let activeCount: Int
  public let peakActive: Int
  public let activeAtTerminal: Int?
  public let lateCompletionCount: Int
}

private enum BoundedMapChildTerminal: Sendable {
  case success, failure, cancelled
}

private enum BoundedMapMonitorLifecycle: Sendable {
  case fresh, running, finished
}

/// Optional observation for `boundedMap`. A terminal is recorded only after the
/// task-group scope has drained every child, so the snapshot can distinguish a
/// completed operation from a cancellation request that is still propagating.
public actor BoundedMapMonitor {
  private var lifecycle: BoundedMapMonitorLifecycle = .fresh
  private var terminal: BoundedMapTerminal?
  private var terminalCount = 0
  private var startedCount = 0
  private var succeededCount = 0
  private var failedCount = 0
  private var cancelledCount = 0
  private var active = 0
  private var peakActive = 0
  private var activeAtTerminal: Int?
  private var lateCompletionCount = 0

  public init() {}

  fileprivate func beginRun() throws {
    guard lifecycle == .fresh else { throw BoundedMapMonitorError.alreadyUsed }
    lifecycle = .running
  }

  fileprivate func childStarted() {
    startedCount += 1
    active += 1
    peakActive = max(peakActive, active)
  }

  fileprivate func childFinished(_ outcome: BoundedMapChildTerminal) {
    active -= 1
    if terminal != nil { lateCompletionCount += 1 }
    switch outcome {
    case .success:
      succeededCount += 1
    case .failure:
      failedCount += 1
    case .cancelled:
      cancelledCount += 1
    }
  }

  fileprivate func recordTerminal(_ value: BoundedMapTerminal) {
    precondition(lifecycle == .running, "monitor terminal requires one active invocation")
    terminalCount += 1
    terminal = value
    activeAtTerminal = active
    lifecycle = .finished
  }

  public func metrics() -> BoundedMapMetrics {
    BoundedMapMetrics(
      terminal: terminal,
      terminalCount: terminalCount,
      startedCount: startedCount,
      succeededCount: succeededCount,
      failedCount: failedCount,
      cancelledCount: cancelledCount,
      activeCount: active,
      peakActive: peakActive,
      activeAtTerminal: activeAtTerminal,
      lateCompletionCount: lateCompletionCount
    )
  }
}

public func boundedMap<Input: Sendable, Output: Sendable>(
  _ input: [Input], limit: Int, monitor: BoundedMapMonitor? = nil,
  operation: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
  precondition(limit > 0, "limit must be positive")
  try await monitor?.beginRun()
  let trackedOperation: @Sendable (Int, Input) async throws -> (Int, Output) = {
    index, value in
    await monitor?.childStarted()
    do {
      try Task.checkCancellation()
      let result = try await operation(value)
      try Task.checkCancellation()
      await monitor?.childFinished(.success)
      return (index, result)
    } catch is CancellationError {
      await monitor?.childFinished(.cancelled)
      throw CancellationError()
    } catch {
      await monitor?.childFinished(.failure)
      throw error
    }
  }

  do {
    try Task.checkCancellation()
    let output = try await withThrowingTaskGroup(
      of: (Int, Output).self,
      returning: [Output].self
    ) { group in
      var iterator = input.enumerated().makeIterator()
      var results: [(Int, Output)] = []
      for _ in 0..<min(limit, input.count) {
        if let (index, value) = iterator.next() {
          group.addTask { try await trackedOperation(index, value) }
        }
      }
      while let result = try await group.next() {
        results.append(result)
        if let (index, value) = iterator.next() {
          group.addTask { try await trackedOperation(index, value) }
        }
      }
      return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
    try Task.checkCancellation()
    await monitor?.recordTerminal(.success)
    return output
  } catch {
    let terminal: BoundedMapTerminal =
      error is CancellationError
      ? .cancelled
      : .failure(errorType: String(reflecting: type(of: error)))
    await monitor?.recordTerminal(terminal)
    throw error
  }
}
