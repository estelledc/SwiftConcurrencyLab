import XCTest

final class SwiftConcurrencyLabUITests: XCTestCase {
    func testInboxAndGuideAreReachable() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tables["inboxTable"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Learn"].tap(); XCTAssertTrue(app.staticTexts["1. 主线程响应性"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Guide"].tap(); XCTAssertTrue(app.tables["guideTable"].waitForExistence(timeout: 5))
    }
    func testStructuredLabRunsAndShowsLogs() throws {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["Learn"].tap(); app.staticTexts["2. 顺序 await 与并行加载"].tap()
        app.buttons["Run Experiment"].tap(); XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '3 个固定任务并发完成'")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Logs"].tap(); XCTAssertTrue(app.tables["labLogTable"].waitForExistence(timeout: 5))
    }
}
