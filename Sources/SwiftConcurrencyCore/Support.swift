import Foundation

public actor LabEventRecorder {
    private var nextID = 1
    private var stored: [LabEvent] = []
    public init() {}
    public func record(runID: UUID, strategy: ConcurrencyStrategy, scenario: LabScenario, phase: LabPhase, _ message: String) {
        stored.append(LabEvent(id: nextID, runID: runID, strategy: strategy, scenario: scenario, phase: phase, message: message))
        nextID += 1
    }
    public func events() -> [LabEvent] { stored }
    public func reset() { nextID = 1; stored.removeAll() }
}

public actor SimulatedMailboxService {
    public init() {}
    public func load(_ resource: String, delayMilliseconds: UInt64, ignoreCancellation: Bool = false) async throws -> String {
        do { try await Task.sleep(for: .milliseconds(Int(delayMilliseconds))) }
        catch where !ignoreCancellation { throw error }
        if !ignoreCancellation { try Task.checkCancellation() }
        return resource
    }
}

public actor LatestValueStore {
    private var value = ""
    public init() {}
    public func submit(query: String, result: String) { if query == value || value.isEmpty { value = result } }
    public func begin(_ query: String) { value = query }
    public func snapshot() -> String { value }
}

public actor UnreadCounter {
    private var value: Int = 0
    public init() {}
    public func increment() { value += 1 }
    public func snapshot() -> Int { value }
}

public actor PinQuota {
    private var remaining: Int
    private var reserved = 0
    public init(remaining: Int) { self.remaining = remaining }
    public func unsafePin(using gate: AsyncGate) async -> Bool {
        guard remaining > 0 else { return false }
        await gate.wait()
        remaining -= 1
        return true
    }
    public func reservedPin(using gate: AsyncGate) async -> Bool {
        guard remaining - reserved > 0 else { return false }
        reserved += 1
        await gate.wait()
        remaining -= 1; reserved -= 1
        return true
    }
    public func snapshot() -> Int { remaining }
}

public actor AsyncGate {
    private var isOpen = false
    public init() {}
    public func open() { isOpen = true }
    public func wait() async { while !isOpen { await Task.yield() } }
}

final class OperationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
}

public enum LegacyCallbackAPI {
    public static func load(_ completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { completion(.success("legacy-result")) }
    }
    public static func loadAsync() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            load { continuation.resume(with: $0) }
        }
    }
}
