import XCTest

final class MockTaskAppUITests: XCTestCase {
  private let bundleIdentifier = "dev.fieldapporchestrator.mock-task"

  @MainActor
  func testMockRecordingEndsWithoutSubmissionAndReturnsHome() throws {
    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
    app.launchArguments = ["-mockDurationSeconds", "3"]
    app.launch()

    let home = app.descendants(matching: .any)["home-screen"]
    XCTAssertTrue(home.waitForExistence(timeout: 10), "Mock app did not show its home screen")
    XCTAssertTrue(app.descendants(matching: .any)["mock-safety-banner"].exists)

    let task = app.buttons["featured-card-mock-task"]
    XCTAssertTrue(task.waitForExistence(timeout: 5))
    task.tap()

    let start = app.buttons["record-start-task"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()

    XCTAssertTrue(
      app.descendants(matching: .any)["recording-screen"].waitForExistence(timeout: 5),
      "Mock recording state did not appear"
    )
    XCTAssertTrue(
      home.waitForExistence(timeout: 8),
      "Mock app did not return home after the configured duration"
    )
    XCTAssertEqual(app.staticTexts["mock-completed-count"].label, "Completed mock sessions: 1")
  }
}
