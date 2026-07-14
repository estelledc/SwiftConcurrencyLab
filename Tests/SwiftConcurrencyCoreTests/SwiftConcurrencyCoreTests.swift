import XCTest
@testable import SwiftConcurrencyCore

final class SwiftConcurrencyCoreTests: XCTestCase {
    func testBoundedMapPreservesInputOrder() async throws {
        let values = try await boundedMap([3, 1, 2], limit: 2) { value in try await Task.sleep(for: .milliseconds(value)); return value * 2 }
        XCTAssertEqual(values, [6, 2, 4])
    }
    func testActorSerializesUnreadWrites() async {
        let counter = UnreadCounter(); await withTaskGroup(of: Void.self) { group in for _ in 0..<100 { group.addTask { await counter.increment() } } }
        let count = await counter.snapshot()
        XCTAssertEqual(count, 100)
    }
    func testReservationPreventsActorReentrancyOverdraft() async {
        let gate = AsyncGate(); let quota = PinQuota(remaining: 1)
        async let first = quota.reservedPin(using: gate); async let second = quota.reservedPin(using: gate)
        await Task.yield(); await gate.open()
        let decisions = await [first, second]
        let remaining = await quota.snapshot()
        XCTAssertEqual(decisions.filter { $0 }.count, 1)
        XCTAssertEqual(remaining, 0)
    }
    func testLegacyBridgeReturnsOnce() async throws {
        let value = try await LegacyCallbackAPI.loadAsync()
        XCTAssertEqual(value, "legacy-result")
    }
    func testLatestWinsKeepsNewestQuery() async {
        let engine = LabEngine(); let outcome = await engine.run(scenario: .latestWinsSearch, strategy: .structured)
        XCTAssertEqual(outcome.values, ["swift-result"])
    }
    func testEveryScenarioHasAnAvailableStrategy() { XCTAssertTrue(LabScenario.allCases.allSatisfy { !$0.supportedStrategies.isEmpty }) }
}
