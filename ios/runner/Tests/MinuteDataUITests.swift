import XCTest

final class MinuteDataUITests: XCTestCase {
  private let bundleIdentifier = "com.bakerdata.minute"
  private let skipPreAndPostEventQuiescence: UInt = 3

  private typealias InteractionBlock = @convention(block) () -> Void
  private typealias InteractionFunction = @convention(c) (
    AnyObject,
    Selector,
    UInt,
    InteractionBlock
  ) -> Void

  private func keepScreenshot(named name: String) {
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func performWithoutQuiescence(
    in app: XCUIApplication,
    _ action: @escaping InteractionBlock
  ) {
    // Minute's featured carousel keeps Core Animation active. XCTest otherwise
    // waits about 60 seconds for quiescence before each interaction. This is an
    // XCTest-private runner hook, not code shipped to the target application.
    let selector = NSSelectorFromString("_performWithInteractionOptions:block:")
    guard app.responds(to: selector), let implementation = app.method(for: selector) else {
      action()
      return
    }
    let function = unsafeBitCast(implementation, to: InteractionFunction.self)
    function(app, selector, skipPreAndPostEventQuiescence, action)
  }

  @MainActor
  func testLaunchAndInspectAccessibilityTree() throws {
    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
    app.launch()

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 20),
      "Minute Data did not reach the foreground. Confirm that it is installed on the device."
    )

    sleep(3)
    keepScreenshot(named: "minute-data-launch")

    print("MINUTE_ACCESSIBILITY_TREE_BEGIN")
    print(app.debugDescription)
    print("MINUTE_ACCESSIBILITY_TREE_END")
  }

  @MainActor
  func testInspectFirstFeaturedTask() throws {
    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

    let featuredTask = app.otherElements
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "featured-card-"))
      .firstMatch
    XCTAssertTrue(featuredTask.waitForExistence(timeout: 15), "No featured task card was found")
    XCTAssertTrue(featuredTask.isHittable, "The first featured task card was not hittable")
    performWithoutQuiescence(in: app) {
      featuredTask.tap()
    }
    sleep(3)

    keepScreenshot(named: "minute-data-task-detail")
    print("MINUTE_TASK_DETAIL_TREE_BEGIN")
    print(app.debugDescription)
    print("MINUTE_TASK_DETAIL_TREE_END")
  }
}
