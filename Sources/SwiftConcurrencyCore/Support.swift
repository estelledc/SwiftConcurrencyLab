import Foundation

public actor LabEventRecorder {
  private var nextID = 1
  private var stored: [LabEvent] = []
  public init() {}
  public func record(
    runID: UUID, strategy: ConcurrencyStrategy, scenario: LabScenario, phase: LabPhase,
    _ message: String
  ) {
    stored.append(
      LabEvent(
        id: nextID, runID: runID, strategy: strategy, scenario: scenario, phase: phase,
        message: message))
    nextID += 1
  }
  public func events() -> [LabEvent] { stored }
  public func reset() {
    nextID = 1
    stored.removeAll()
  }
}

public actor SimulatedMailboxService {
  public init() {}
  public func load(_ resource: String, delayMilliseconds: UInt64, ignoreCancellation: Bool = false)
    async throws -> String
  {
    do { try await Task.sleep(for: .milliseconds(Int(delayMilliseconds))) } catch
      where !ignoreCancellation
    { throw error }
    if !ignoreCancellation { try Task.checkCancellation() }
    return resource
  }
}

public actor LatestValueStore {
  private var value = ""
  public init() {}
  public func submit(query: String, result: String) {
    if query == value || value.isEmpty { value = result }
  }
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
    remaining -= 1
    reserved -= 1
    return true
  }
  public func snapshot() -> Int { remaining }
}

public actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  public init() {}
  public func open() {
    isOpen = true
    let suspended = waiters
    waiters.removeAll()
    for continuation in suspended {
      continuation.resume()
    }
  }
  public func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
  public func waitUntilWaiters(_ expectedCount: Int) async {
    while waiters.count < expectedCount { await Task.yield() }
  }
}

public enum CellReuseIdentity {
  public static func canCommit(
    cancelled: Bool,
    representedID: String?,
    resultID: String
  ) -> Bool {
    !cancelled && representedID == resultID
  }
}

public struct CellReuseProbeResult: Equatable, Sendable {
  public let committedID: String?
  public let rejectedID: String?
  public let cancellationRequested: Bool
  public let events: [String]
}

private actor CellReuseCommitState {
  private var representedID: String?
  private var committedID: String?
  private var rejectedID: String?
  private var cancellationRequested = false
  private var events: [String] = []

  func configure(id: String) {
    representedID = id
    events.append("configure=\(id)")
  }

  func cancel(id: String) {
    cancellationRequested = true
    events.append("cancel=\(id)")
  }

  func commit(id: String, cancelled: Bool) -> Bool {
    guard
      CellReuseIdentity.canCommit(
        cancelled: cancelled,
        representedID: representedID,
        resultID: id
      )
    else {
      rejectedID = id
      events.append("reject=\(id)")
      return false
    }
    committedID = id
    events.append("commit=\(id)")
    return true
  }

  func snapshot() -> CellReuseProbeResult {
    CellReuseProbeResult(
      committedID: committedID,
      rejectedID: rejectedID,
      cancellationRequested: cancellationRequested,
      events: events
    )
  }
}

/// Runs a deterministic configure -> reuse/cancel -> stale-result rejection chain.
/// The old load is suspended behind a controllable gate and deliberately resumes
/// after the cell represents the new ID, so cancellation and identity are both tested.
public func runCellReuseProbe() async -> CellReuseProbeResult {
  let state = CellReuseCommitState()
  let oldLoadGate = AsyncGate()

  await state.configure(id: "message-old")
  let oldLoad = Task {
    await oldLoadGate.wait()
    return await state.commit(id: "message-old", cancelled: Task.isCancelled)
  }
  await oldLoadGate.waitUntilWaiters(1)

  oldLoad.cancel()
  await state.cancel(id: "message-old")
  await state.configure(id: "message-new")
  _ = await state.commit(id: "message-new", cancelled: false)

  await oldLoadGate.open()
  _ = await oldLoad.value
  return await state.snapshot()
}

final class OperationAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Int: String] = [:]
  func append(_ value: String, at index: Int) {
    lock.lock()
    defer { lock.unlock() }
    values[index] = value
  }
  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return values.sorted { $0.key < $1.key }.map(\.value)
  }
}

public enum LegacyCallbackAPI {
  public static func load(_ completion: @escaping @Sendable (Result<String, Error>) -> Void) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
      completion(.success("legacy-result"))
    }
  }
  public static func loadAsync() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      load { continuation.resume(with: $0) }
    }
  }
}
