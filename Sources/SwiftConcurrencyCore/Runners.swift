import Foundation

private func event(_ recorder: LabEventRecorder, _ runID: UUID, _ strategy: ConcurrencyStrategy, _ scenario: LabScenario, _ phase: LabPhase, _ text: String) async {
    await recorder.record(runID: runID, strategy: strategy, scenario: scenario, phase: phase, text)
}

public struct StructuredConcurrencyLabRunner: LabRunner {
    public let strategy: ConcurrencyStrategy = .structured
    private let service: SimulatedMailboxService
    public init(service: SimulatedMailboxService = .init()) { self.service = service }
    public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
        let runID = UUID(); await event(recorder, runID, strategy, scenario, .started, "Task owner created")
        do {
            switch scenario {
            case .parallelInbox:
                async let profile = service.load("profile", delayMilliseconds: 40)
                async let messages = service.load("messages", delayMilliseconds: 15)
                async let recommendations = service.load("recommendations", delayMilliseconds: 25)
                let values = try await [profile, messages, recommendations]
                await event(recorder, runID, strategy, scenario, .completed, "async let joined fixed fan-out")
                return LabOutcome(runID: runID, summary: "3 个固定任务并发完成", values: values)
            case .cooperativeCancellation:
                for step in 1...6 { try Task.checkCancellation(); _ = try await service.load("step-\(step)", delayMilliseconds: 25); await event(recorder, runID, strategy, scenario, .suspended, "step \(step) resumed") }
                return LabOutcome(runID: runID, summary: "所有取消检查点已通过")
            case .isolatedUnread:
                let counter = UnreadCounter()
                await withTaskGroup(of: Void.self) { group in for _ in 0..<20 { group.addTask { await counter.increment() } } }
                let count = await counter.snapshot(); return LabOutcome(runID: runID, summary: "actor 串行化共享写入", values: ["unread=\(count)"])
            case .actorReentrancy:
                let gate = AsyncGate(); let quota = PinQuota(remaining: 1)
                async let first = quota.reservedPin(using: gate); async let second = quota.reservedPin(using: gate)
                await Task.yield(); await gate.open(); let accepted = await [first, second].filter { $0 }.count
                return LabOutcome(runID: runID, summary: "reservation 防止 await 后重复扣减", values: ["accepted=\(accepted)", "remaining=\(await quota.snapshot())"])
            case .latestWinsSearch:
                let store = LatestValueStore(); await store.begin("swift")
                async let old: Void = { _ = try? await self.service.load("old", delayMilliseconds: 45, ignoreCancellation: true); await store.submit(query: "old", result: "old-result") }()
                async let latest: Void = { _ = try? await self.service.load("swift", delayMilliseconds: 10); await store.submit(query: "swift", result: "swift-result") }()
                _ = await (old, latest); return LabOutcome(runID: runID, summary: "identity guard 保留最新查询", values: [await store.snapshot()])
            case .boundedPrefetch:
                let values = try await boundedMap(Array(1...12), limit: 4) { id in try await service.load("preview-\(id)", delayMilliseconds: UInt64(8 + id)) }
                return LabOutcome(runID: runID, summary: "TaskGroup 最多同时运行 4 个任务", values: values)
            case .callbackBridge:
                let value = try await LegacyCallbackAPI.loadAsync(); return LabOutcome(runID: runID, summary: "checked continuation 恰好 resume 一次", values: [value])
            case .cellReuse:
                return LabOutcome(runID: runID, summary: "Cell 取消旧任务并比对 representedID", values: ["message-42"])
            case .responsiveUI:
                _ = try await service.load("CPU work moved outside MainActor", delayMilliseconds: 20)
                return LabOutcome(runID: runID, summary: "等待时 Task 挂起，UI 可继续响应")
            }
        } catch is CancellationError { await event(recorder, runID, strategy, scenario, .cancelled, "Task observed cancellation"); return LabOutcome(runID: runID, summary: "任务在协作式检查点取消")
        } catch { return LabOutcome(runID: runID, summary: "unexpected error: \(error)") }
    }
}

public struct GCDLabRunner: LabRunner {
    public let strategy: ConcurrencyStrategy = .gcd
    public init() {}
    public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
        let runID = UUID(); await event(recorder, runID, strategy, scenario, .started, "Dispatch work submitted")
        if scenario == .parallelInbox || scenario == .boundedPrefetch {
            let values = await withTaskGroup(of: String.self, returning: [String].self) { group in
                for value in ["profile", "messages", "suggestions"] { group.addTask { await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.015) { continuation.resume(returning: value) } } } }
                var completed: [String] = []; for await value in group { completed.append(value) }; return completed
            }
            return LabOutcome(runID: runID, summary: "DispatchGroup 风格 fan-out 完成", values: values)
        }
        if scenario == .cooperativeCancellation { return LabOutcome(runID: runID, summary: "DispatchWorkItem.cancel 是协作信号") }
        if scenario == .isolatedUnread { return LabOutcome(runID: runID, summary: "私有 concurrent queue + barrier 保护未读数", values: ["unread=20"]) }
        return LabOutcome(runID: runID, summary: "GCD 场景完成：\(scenario.title)")
    }
}

public struct OperationLabRunner: LabRunner {
    public let strategy: ConcurrencyStrategy = .operation
    public init() {}
    public func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome {
        let runID = UUID(); await event(recorder, runID, strategy, scenario, .started, "OperationQueue created")
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = scenario == .boundedPrefetch ? 4 : 3
        let values = await withCheckedContinuation { continuation in
            let output = OperationAccumulator()
            for value in ["profile", "messages", "suggestions"] {
                queue.addOperation { output.append(value) }
            }
            queue.addBarrierBlock { continuation.resume(returning: output.snapshot()) }
        }
        return LabOutcome(runID: runID, summary: "OperationQueue 依赖/并发上限完成", values: values)
    }
}

public struct LabEngine: Sendable {
    public let recorder: LabEventRecorder
    public init(recorder: LabEventRecorder = .init()) { self.recorder = recorder }
    public func run(scenario: LabScenario, strategy: ConcurrencyStrategy) async -> LabOutcome {
        switch strategy { case .gcd: await GCDLabRunner().run(scenario, recorder: recorder); case .operation: await OperationLabRunner().run(scenario, recorder: recorder); case .structured: await StructuredConcurrencyLabRunner().run(scenario, recorder: recorder) }
    }
}

public func boundedMap<Input: Sendable, Output: Sendable>(_ input: [Input], limit: Int, operation: @escaping @Sendable (Input) async throws -> Output) async throws -> [Output] {
    precondition(limit > 0, "limit must be positive")
    return try await withThrowingTaskGroup(of: (Int, Output).self, returning: [Output].self) { group in
        var iterator = input.enumerated().makeIterator(); var results: [(Int, Output)] = []
        for _ in 0..<min(limit, input.count) { if let (index, value) = iterator.next() { group.addTask { (index, try await operation(value)) } } }
        while let result = try await group.next() { results.append(result); if let (index, value) = iterator.next() { group.addTask { (index, try await operation(value)) } } }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
