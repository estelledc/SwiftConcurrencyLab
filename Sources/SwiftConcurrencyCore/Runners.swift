import Foundation

private func event(
  _ recorder: LabEventRecorder, _ runID: UUID, _ strategy: ConcurrencyStrategy,
  _ scenario: LabScenario, _ phase: LabPhase, _ text: String
) async {
  await recorder.record(runID: runID, strategy: strategy, scenario: scenario, phase: phase, text)
}

private func completed(
  _ recorder: LabEventRecorder,
  _ runID: UUID,
  _ strategy: ConcurrencyStrategy,
  _ scenario: LabScenario,
  summary: String,
  values: [String] = []
) async -> LabOutcome {
  await event(recorder, runID, strategy, scenario, .completed, summary)
  return LabOutcome(runID: runID, summary: summary, values: values)
}

public struct StructuredConcurrencyLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .structured
  private let service: SimulatedMailboxService
  private let actorReentrancyMode: ActorReentrancyMode
  public init(
    service: SimulatedMailboxService = .init(),
    actorReentrancyMode: ActorReentrancyMode = .reserved
  ) {
    self.service = service
    self.actorReentrancyMode = actorReentrancyMode
  }
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    await event(recorder, runID, strategy, scenario, .started, "Task owner created")
    do {
      switch scenario {
      case .parallelInbox:
        for resource in ["profile", "messages", "recommendations"] {
          await event(recorder, runID, strategy, scenario, .scheduled, "\(resource) scheduled")
        }
        async let profile = service.load("profile", delayMilliseconds: 40)
        async let messages = service.load("messages", delayMilliseconds: 15)
        async let recommendations = service.load("recommendations", delayMilliseconds: 25)
        let values = try await [profile, messages, recommendations]
        return await completed(
          recorder, runID, strategy, scenario, summary: "3 个固定任务并发完成", values: values)
      case .cooperativeCancellation:
        for step in 1...6 {
          try Task.checkCancellation()
          _ = try await service.load("step-\(step)", delayMilliseconds: 25)
          await event(recorder, runID, strategy, scenario, .suspended, "step \(step) resumed")
        }
        return await completed(recorder, runID, strategy, scenario, summary: "所有取消检查点已通过")
      case .isolatedUnread:
        let counter = UnreadCounter()
        await withTaskGroup(of: Void.self) { group in
          for _ in 0..<20 { group.addTask { await counter.increment() } }
        }
        let count = await counter.snapshot()
        return await completed(
          recorder, runID, strategy, scenario, summary: "actor 串行化共享写入", values: ["unread=\(count)"]
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
          recorder, runID, strategy, scenario,
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
          recorder, runID, strategy, scenario, summary: "identity guard 保留最新查询",
          values: [await store.snapshot()])
      case .boundedPrefetch:
        await event(
          recorder, runID, strategy, scenario, .scheduled, "12 previews scheduled with limit=4")
        let values = try await boundedMap(Array(1...12), limit: 4) { id in
          try await service.load("preview-\(id)", delayMilliseconds: UInt64(8 + id))
        }
        return await completed(
          recorder, runID, strategy, scenario, summary: "TaskGroup 最多同时运行 4 个任务", values: values)
      case .callbackBridge:
        let value = try await LegacyCallbackAPI.loadAsync()
        return await completed(
          recorder, runID, strategy, scenario, summary: "checked continuation 恰好 resume 一次",
          values: [value])
      case .cellReuse:
        await event(recorder, runID, strategy, scenario, .scheduled, "configure message-old")
        let result = await runCellReuseProbe()
        await event(recorder, runID, strategy, scenario, .cancelled, "reuse cancelled message-old")
        await event(
          recorder, runID, strategy, scenario, .warning, "stale commit message-old rejected")
        return await completed(
          recorder, runID, strategy, scenario, summary: "复用链拒绝旧提交",
          values: [
            "committed=\(result.committedID ?? "none")",
            "rejected=\(result.rejectedID ?? "none")",
            "cancelled=\(result.cancellationRequested)",
          ])
      case .responsiveUI:
        await event(recorder, runID, strategy, scenario, .scheduled, "background work scheduled")
        _ = try await service.load("CPU work moved outside MainActor", delayMilliseconds: 20)
        return await completed(recorder, runID, strategy, scenario, summary: "等待时 Task 挂起，UI 可继续响应")
      }
    } catch is CancellationError {
      await event(recorder, runID, strategy, scenario, .cancelled, "Task observed cancellation")
      return LabOutcome(runID: runID, summary: "任务在协作式检查点取消")
    } catch { return LabOutcome(runID: runID, summary: "unexpected error: \(error)") }
  }
}

public struct GCDLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .gcd
  public init() {}
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    await event(recorder, runID, strategy, scenario, .started, "Dispatch work submitted")
    let resources = ["profile", "messages", "recommendations"]
    for resource in resources {
      await event(recorder, runID, strategy, scenario, .scheduled, "\(resource) dispatched")
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
      recorder, runID, strategy, scenario, summary: "Dispatch fan-out 完成，按输入顺序提交", values: values)
  }
}

public struct OperationLabRunner: LabRunner {
  public let strategy: ConcurrencyStrategy = .operation
  public init() {}
  public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
    let runID = UUID()
    await event(recorder, runID, strategy, scenario, .started, "OperationQueue created")
    let resources = ["profile", "messages", "recommendations"]
    for resource in resources {
      await event(recorder, runID, strategy, scenario, .scheduled, "\(resource) operation enqueued")
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
      recorder, runID, strategy, scenario, summary: "OperationQueue fan-out 完成，按输入顺序提交",
      values: values)
  }
}

public struct LabEngine: Sendable {
  public let recorder: LabEventRecorder
  public init(recorder: LabEventRecorder = .init()) { self.recorder = recorder }
  public func run(
    scenario: LabScenario,
    strategy: ConcurrencyStrategy,
    actorReentrancyMode: ActorReentrancyMode = .reserved
  ) async -> LabOutcome {
    guard scenario.supportedStrategies.contains(strategy) else {
      let runID = UUID()
      await recorder.record(
        runID: runID, strategy: strategy, scenario: scenario, phase: .warning,
        "Strategy is not implemented for this scenario")
      return LabOutcome(runID: runID, summary: "\(strategy.rawValue) 尚未实现 \(scenario.title)")
    }
    switch strategy {
    case .gcd:
      return await GCDLabRunner().run(scenario, recorder: recorder)
    case .operation:
      return await OperationLabRunner().run(scenario, recorder: recorder)
    case .structured:
      return await StructuredConcurrencyLabRunner(actorReentrancyMode: actorReentrancyMode).run(
        scenario, recorder: recorder)
    }
  }
}

public func boundedMap<Input: Sendable, Output: Sendable>(
  _ input: [Input], limit: Int, operation: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
  precondition(limit > 0, "limit must be positive")
  return try await withThrowingTaskGroup(of: (Int, Output).self, returning: [Output].self) {
    group in
    var iterator = input.enumerated().makeIterator()
    var results: [(Int, Output)] = []
    for _ in 0..<min(limit, input.count) {
      if let (index, value) = iterator.next() {
        group.addTask { (index, try await operation(value)) }
      }
    }
    while let result = try await group.next() {
      results.append(result)
      if let (index, value) = iterator.next() {
        group.addTask { (index, try await operation(value)) }
      }
    }
    return results.sorted { $0.0 < $1.0 }.map(\.1)
  }
}
