import XCTest

@testable import SwiftConcurrencyCore

private enum InjectedFailure: Error {
  case item(Int)
}

private actor StartBarrier {
  private var startedCount = 0
  private var waiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func markStarted() {
    startedCount += 1
    let ready = waiters.filter { startedCount >= $0.expected }
    waiters.removeAll { startedCount >= $0.expected }
    for waiter in ready { waiter.continuation.resume() }
  }

  func waitUntilStarted(_ expected: Int) async {
    guard startedCount < expected else { return }
    await withCheckedContinuation { continuation in
      waiters.append((expected, continuation))
    }
  }
}

final class BoundedMapReliabilityTests: XCTestCase {
  func testSuccessRecordsOneTerminalOnlyAfterEveryChildDrains() async throws {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let releaseGate = AsyncGate()

    let task = Task {
      try await boundedMap(Array(0..<8), limit: 4, monitor: monitor) { value in
        await startBarrier.markStarted()
        await releaseGate.wait()
        return value * 2
      }
    }

    await startBarrier.waitUntilStarted(4)
    await releaseGate.open()

    let values = try await task.value
    let metrics = await monitor.metrics()
    XCTAssertEqual(values, Array(0..<8).map { $0 * 2 })
    assertTerminalInvariants(metrics, terminal: .success)
    XCTAssertEqual(metrics.startedCount, 8)
    XCTAssertEqual(metrics.succeededCount, 8)
    XCTAssertEqual(metrics.failedCount, 0)
    XCTAssertEqual(metrics.cancelledCount, 0)
    XCTAssertEqual(metrics.peakActive, 4)
  }

  func testInjectedFailureDrainsSiblingsBeforeRecordingTypedTerminal() async {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let cancellationBarrier = StartBarrier()
    let failureGate = AsyncGate()
    let siblingGate = AsyncGate()

    let task = Task {
      try await boundedMap(Array(0..<8), limit: 4, monitor: monitor) { value in
        await startBarrier.markStarted()
        if value == 0 {
          await failureGate.wait()
          throw InjectedFailure.item(value)
        }
        await withTaskCancellationHandler {
          await siblingGate.wait()
        } onCancel: {
          Task { await cancellationBarrier.markStarted() }
        }
        return value
      }
    }

    await startBarrier.waitUntilStarted(4)
    await failureGate.open()
    await cancellationBarrier.waitUntilStarted(3)

    let whileDraining = await monitor.metrics()
    XCTAssertNil(whileDraining.terminal)
    XCTAssertEqual(whileDraining.terminalCount, 0)
    XCTAssertEqual(whileDraining.activeCount, 3)

    await siblingGate.open()

    do {
      _ = try await task.value
      XCTFail("Expected the injected child failure")
    } catch InjectedFailure.item(0) {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let metrics = await monitor.metrics()
    guard case .failure(let errorType) = metrics.terminal else {
      let terminal = String(describing: metrics.terminal)
      return XCTFail("Expected a typed failure terminal, got \(terminal)")
    }
    XCTAssertTrue(errorType.contains("InjectedFailure"))
    assertDrainInvariants(metrics)
    XCTAssertEqual(metrics.startedCount, 4)
    XCTAssertEqual(metrics.succeededCount, 0)
    XCTAssertEqual(metrics.failedCount, 1)
    XCTAssertEqual(metrics.cancelledCount, 3)
    XCTAssertEqual(metrics.peakActive, 4)
  }

  func testTypedFailureIsNotRelabelledWhenParentIsAlsoCancelled() async {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let cancellationBarrier = StartBarrier()
    let failureGate = AsyncGate()
    let siblingGate = AsyncGate()

    let task = Task {
      try await boundedMap(Array(0..<2), limit: 2, monitor: monitor) { value in
        await startBarrier.markStarted()
        if value == 0 {
          await failureGate.wait()
          throw InjectedFailure.item(value)
        }
        await withTaskCancellationHandler {
          await siblingGate.wait()
        } onCancel: {
          Task { await cancellationBarrier.markStarted() }
        }
        return value
      }
    }

    await startBarrier.waitUntilStarted(2)
    task.cancel()
    await cancellationBarrier.waitUntilStarted(1)
    await failureGate.open()
    while await monitor.metrics().failedCount == 0 { await Task.yield() }
    await siblingGate.open()

    do {
      _ = try await task.value
      XCTFail("Expected the typed child failure")
    } catch InjectedFailure.item(0) {
      // Expected: cancellation must not rewrite the error returned to the caller.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let metrics = await monitor.metrics()
    guard case .failure(let errorType) = metrics.terminal else {
      return XCTFail("Expected typed failure, got \(String(describing: metrics.terminal))")
    }
    XCTAssertTrue(errorType.contains("InjectedFailure"))
    assertDrainInvariants(metrics)
    XCTAssertEqual(metrics.failedCount, 1)
    XCTAssertEqual(metrics.cancelledCount, 1)
  }

  func testParentCancellationDrainsChildrenBeforeRecordingTerminal() async {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()

    let task = Task {
      try await boundedMap(Array(0..<8), limit: 4, monitor: monitor) { value in
        await startBarrier.markStarted()
        try await Task.sleep(for: .seconds(60))
        return value
      }
    }

    await startBarrier.waitUntilStarted(4)
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected parent cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let metrics = await monitor.metrics()
    assertTerminalInvariants(metrics, terminal: .cancelled)
    XCTAssertEqual(metrics.startedCount, 4)
    XCTAssertEqual(metrics.succeededCount, 0)
    XCTAssertEqual(metrics.failedCount, 0)
    XCTAssertEqual(metrics.cancelledCount, 4)
    XCTAssertEqual(metrics.peakActive, 4)
  }

  func testParentCancellationIsObservedAfterOperationIgnoresItUntilRelease() async {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let releaseGate = AsyncGate()

    let task = Task {
      try await boundedMap(Array(0..<2), limit: 2, monitor: monitor) { value in
        await startBarrier.markStarted()
        await releaseGate.wait()
        return value
      }
    }

    await startBarrier.waitUntilStarted(2)
    task.cancel()
    await releaseGate.open()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation after the non-cooperative operation returned")
    } catch is CancellationError {
      // Expected: the wrapper checks cancellation before accepting each result.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let metrics = await monitor.metrics()
    assertTerminalInvariants(metrics, terminal: .cancelled)
    XCTAssertEqual(metrics.startedCount, 2)
    XCTAssertEqual(metrics.succeededCount, 0)
    XCTAssertEqual(metrics.failedCount, 0)
    XCTAssertEqual(metrics.cancelledCount, 2)
    XCTAssertEqual(metrics.peakActive, 2)
  }

  func testMonitorRejectsSequentialReuseWithoutPollutingTheFirstRun() async throws {
    let monitor = BoundedMapMonitor()
    _ = try await boundedMap([1], limit: 1, monitor: monitor) { $0 }

    do {
      _ = try await boundedMap([2], limit: 1, monitor: monitor) { $0 }
      XCTFail("Expected a one-shot monitor error")
    } catch BoundedMapMonitorError.alreadyUsed {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let metrics = await monitor.metrics()
    assertTerminalInvariants(metrics, terminal: .success)
    XCTAssertEqual(metrics.startedCount, 1)
    XCTAssertEqual(metrics.succeededCount, 1)
  }

  func testMonitorRejectsConcurrentReuseWithoutMergingTaskTrees() async throws {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let releaseGate = AsyncGate()
    let first = Task {
      try await boundedMap([1], limit: 1, monitor: monitor) { value in
        await startBarrier.markStarted()
        await releaseGate.wait()
        return value
      }
    }
    await startBarrier.waitUntilStarted(1)

    do {
      _ = try await boundedMap([2], limit: 1, monitor: monitor) { $0 }
      XCTFail("Expected concurrent reuse to be rejected")
    } catch BoundedMapMonitorError.alreadyUsed {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    await releaseGate.open()
    let firstValues = try await first.value
    XCTAssertEqual(firstValues, [1])
    let metrics = await monitor.metrics()
    assertTerminalInvariants(metrics, terminal: .success)
    XCTAssertEqual(metrics.startedCount, 1)
    XCTAssertEqual(metrics.peakActive, 1)
  }

  func testDeterministicSuccessFailureAndCancellationMatrixFor100Rounds() async throws {
    for _ in 0..<100 {
      let success = try await runSuccessRound()
      assertTerminalInvariants(success, terminal: .success)
      XCTAssertEqual(success.startedCount, 4)
      XCTAssertEqual(success.succeededCount, 4)
      XCTAssertEqual(success.peakActive, 2)

      let failure = await runFailureRound()
      guard case .failure(let errorType) = failure.terminal else {
        XCTFail("Expected failure terminal")
        continue
      }
      XCTAssertTrue(errorType.contains("InjectedFailure"))
      assertDrainInvariants(failure)
      XCTAssertEqual(failure.startedCount, 2)
      XCTAssertEqual(failure.failedCount, 1)
      XCTAssertEqual(failure.cancelledCount, 1)
      XCTAssertEqual(failure.peakActive, 2)

      let cancellation = await runCancellationRound()
      assertTerminalInvariants(cancellation, terminal: .cancelled)
      XCTAssertEqual(cancellation.startedCount, 2)
      XCTAssertEqual(cancellation.cancelledCount, 2)
      XCTAssertEqual(cancellation.peakActive, 2)
    }
  }

  func testBoundedPrefetchCancellationProbeRecordsOneCancelledTerminalAndNoCompletion() async {
    let engine = LabEngine()
    let task = Task {
      await engine.run(
        scenario: .boundedPrefetch,
        strategy: .structured,
        boundedPrefetchMode: .cancellationProbe
      )
    }

    while true {
      let phases = await engine.recorder.events().map(\.phase)
      if phases.contains(.scheduled) { break }
      await Task.yield()
    }
    task.cancel()

    let outcome = await task.value
    let events = await engine.recorder.events().filter { $0.runID == outcome.runID }
    XCTAssertEqual(events.filter { $0.phase == .cancelled }.count, 1)
    XCTAssertFalse(events.contains { $0.phase == .completed })
    XCTAssertEqual(events.map(\.phase), [.started, .scheduled, .cancelled])
  }

  private func runSuccessRound() async throws -> BoundedMapMetrics {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let releaseGate = AsyncGate()
    let task = Task {
      try await boundedMap(Array(0..<4), limit: 2, monitor: monitor) { value in
        await startBarrier.markStarted()
        await releaseGate.wait()
        return value
      }
    }
    await startBarrier.waitUntilStarted(2)
    await releaseGate.open()
    _ = try await task.value
    return await monitor.metrics()
  }

  private func runFailureRound() async -> BoundedMapMetrics {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let failureGate = AsyncGate()
    let task = Task {
      try await boundedMap(Array(0..<4), limit: 2, monitor: monitor) { value in
        await startBarrier.markStarted()
        if value == 0 {
          await failureGate.wait()
          throw InjectedFailure.item(value)
        }
        try await Task.sleep(for: .seconds(60))
        return value
      }
    }
    await startBarrier.waitUntilStarted(2)
    await failureGate.open()
    _ = try? await task.value
    return await monitor.metrics()
  }

  private func runCancellationRound() async -> BoundedMapMetrics {
    let monitor = BoundedMapMonitor()
    let startBarrier = StartBarrier()
    let task = Task {
      try await boundedMap(Array(0..<4), limit: 2, monitor: monitor) { value in
        await startBarrier.markStarted()
        try await Task.sleep(for: .seconds(60))
        return value
      }
    }
    await startBarrier.waitUntilStarted(2)
    task.cancel()
    _ = try? await task.value
    return await monitor.metrics()
  }

  private func assertTerminalInvariants(
    _ metrics: BoundedMapMetrics,
    terminal: BoundedMapTerminal,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(metrics.terminal, terminal, file: file, line: line)
    assertDrainInvariants(metrics, file: file, line: line)
  }

  private func assertDrainInvariants(
    _ metrics: BoundedMapMetrics,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(metrics.terminalCount, 1, file: file, line: line)
    XCTAssertEqual(metrics.activeAtTerminal, 0, file: file, line: line)
    XCTAssertEqual(metrics.lateCompletionCount, 0, file: file, line: line)
  }
}
