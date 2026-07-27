import XCTest

@MainActor
final class SwiftConcurrencyLabUITests: XCTestCase {
  private func openLab(_ identifier: String, in app: XCUIApplication) {
    let learn = app.tabBars.buttons["Learn"]
    XCTAssertTrue(learn.waitForExistence(timeout: 5))
    learn.tap()

    let cell = app.cells[identifier]
    if !cell.waitForExistence(timeout: 2) {
      learn.tap()
    }
    XCTAssertTrue(cell.waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.staticTexts["哪种写法会让主线程无法继续处理交互？"].exists,
      "The lab list should show titles only."
    )
    for _ in 0..<3 where !app.staticTexts["labGoal"].exists {
      cell.tap()
      if app.staticTexts["labGoal"].waitForExistence(timeout: 2) { break }
    }
    XCTAssertTrue(app.staticTexts["labGoal"].exists)
  }

  func testInboxAndLabConsoleAreReachable() throws {
    let app = XCUIApplication()
    app.launch()
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    let windowFrame = window.frame
    XCTAssertGreaterThan(
      windowFrame.width,
      350,
      "The app must use the modern full-size viewport, not the 320-point compatibility mode."
    )
    XCTAssertGreaterThan(
      windowFrame.height,
      700,
      "The app must not launch inside a 480-point letterboxed compatibility viewport."
    )
    XCTAssertTrue(app.tables["inboxTable"].waitForExistence(timeout: 5))
    openLab("lab_responsiveUI", in: app)
    XCTAssertTrue(app.staticTexts["labGoal"].exists)
    XCTAssertTrue(app.staticTexts["labSourceCue"].exists)
    XCTAssertTrue(app.staticTexts["labActionCue"].exists)
    XCTAssertTrue(app.staticTexts["labDocsCue"].exists)
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Runners.swift'")
      ).firstMatch.exists
    )
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(
          format: "label CONTAINS 'docs/lab-guide.md#lab-responsive-ui'"
        )
      ).firstMatch.exists
    )
    XCTAssertTrue(app.buttons["runExperimentButton"].exists)
    XCTAssertTrue(app.navigationBars.buttons["Logs"].exists)
  }

  func testStructuredLabRunsAndShowsLogs() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_parallelInbox", in: app)
    app.buttons["runExperimentButton"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(
          format: "label CONTAINS '3 个固定任务并发完成' AND label CONTAINS '3 values in Logs'"
        )
      ).firstMatch.waitForExistence(timeout: 5)
    )
    app.navigationBars.buttons["Logs"].tap()
    XCTAssertTrue(app.tables["labLogTable"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(
          format: "label CONTAINS 'Swift Concurrency · scheduled'"
        )
      ).firstMatch.waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(
          format: "label CONTAINS 'Swift Concurrency · uiCommit'"
        )
      ).firstMatch.waitForExistence(timeout: 5)
    )
    app.navigationBars.buttons["Reset"].tap()
    XCTAssertTrue(
      app.staticTexts[
        "No events yet. Run an experiment first."
      ].waitForExistence(timeout: 5)
    )
  }

  func testActorReentrancyRunsUnsafeAndReservedControls() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_actorReentrancy", in: app)

    let mode = app.segmentedControls["actorReentrancyModeControl"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    mode.buttons["Unsafe"].tap()
    app.buttons["runExperimentButton"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'accepted=2' AND label CONTAINS 'remaining=-1'")
      ).firstMatch.waitForExistence(timeout: 5)
    )

    mode.buttons["Reserved"].tap()
    app.buttons["runExperimentButton"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'accepted=1' AND label CONTAINS 'remaining=0'")
      ).firstMatch.waitForExistence(timeout: 5)
    )

    app.buttons["resetExperimentButton"].tap()
    XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 5))
    app.navigationBars.buttons["Logs"].tap()
    XCTAssertTrue(
      app.staticTexts[
        "No events yet. Run an experiment first."
      ].waitForExistence(timeout: 5)
    )
  }

  func testCellReuseRunExecutesAndReportsTheRejectedOldCommit() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_cellReuse", in: app)
    app.buttons["runExperimentButton"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(
          format: "label CONTAINS 'committed=message-new' AND label CONTAINS 'rejected=message-old'"
        )
      ).firstMatch.waitForExistence(timeout: 5)
    )
  }

  func testBoundedPrefetchCancellationHasOneTerminalAndNoLateUICommit() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_boundedPrefetch", in: app)

    let mode = app.segmentedControls["boundedPrefetchModeControl"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    mode.buttons["Cancellation Probe"].tap()
    app.buttons["runExperimentButton"].tap()
    app.buttons["cancelExperimentButton"].tap()

    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Cancellation requested'")
      ).firstMatch.waitForExistence(timeout: 5)
    )

    app.navigationBars.buttons["Logs"].tap()
    XCTAssertTrue(app.tables["labLogTable"].waitForExistence(timeout: 5))
    let cancelledEvents = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS 'Swift Concurrency · cancelled'")
    )
    XCTAssertTrue(cancelledEvents.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(cancelledEvents.count, 1)
    XCTAssertEqual(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · completed'")
      ).count,
      0
    )
    XCTAssertEqual(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · uiCommit'")
      ).count,
      0
    )

    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["runExperimentButton"].isEnabled)
  }

  func testCompletedRunCannotBeRelabeledAsCancellation() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_boundedPrefetch", in: app)

    app.buttons["runExperimentButton"].tap()
    let completedStatus = app.staticTexts.containing(
      NSPredicate(
        format: "label CONTAINS 'TaskGroup 最多同时运行 4 个任务' AND label CONTAINS '12 values'"
      )
    ).firstMatch
    XCTAssertTrue(completedStatus.waitForExistence(timeout: 5))

    app.buttons["cancelExperimentButton"].tap()
    XCTAssertTrue(completedStatus.exists)
    XCTAssertFalse(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Cancellation requested'")
      ).firstMatch.exists
    )

    app.navigationBars.buttons["Logs"].tap()
    XCTAssertTrue(app.tables["labLogTable"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · uiCommit'")
      ).firstMatch.waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · cancelled'")
      ).count,
      0
    )
  }

  func testCancelThenResetDoesNotAllowTheOldTerminalToReappear() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_boundedPrefetch", in: app)

    let mode = app.segmentedControls["boundedPrefetchModeControl"]
    mode.buttons["Cancellation Probe"].tap()
    app.buttons["runExperimentButton"].tap()
    app.buttons["cancelExperimentButton"].tap()
    app.buttons["resetExperimentButton"].tap()

    XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 5))
    app.navigationBars.buttons["Logs"].tap()
    let empty = app.staticTexts["No events yet. Run an experiment first."]
    XCTAssertTrue(empty.waitForExistence(timeout: 5))
    sleep(1)
    XCTAssertTrue(empty.exists)
    XCTAssertEqual(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · cancelled'")
      ).count,
      0
    )
  }

  func testLogsResetRejectsAPendingOldUICommit() throws {
    let app = XCUIApplication()
    app.launch()
    openLab("lab_boundedPrefetch", in: app)

    app.buttons["runExperimentButton"].tap()
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'TaskGroup 最多同时运行 4 个任务'")
      ).firstMatch.waitForExistence(timeout: 5)
    )
    app.navigationBars.buttons["Logs"].tap()
    XCTAssertTrue(app.tables["labLogTable"].waitForExistence(timeout: 5))
    app.navigationBars.buttons["Reset"].tap()

    let empty = app.staticTexts["No events yet. Run an experiment first."]
    XCTAssertTrue(empty.waitForExistence(timeout: 5))
    sleep(1)
    XCTAssertTrue(empty.exists)
    XCTAssertEqual(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS 'Swift Concurrency · uiCommit'")
      ).count,
      0
    )
  }
}
