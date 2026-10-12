import XCTest

@testable import FieldAppControllerCore

private actor CourseFixtureSession: AppAutomationSession {
  enum Screen {
    case home
    case taskReady
    case recording
    case completionPending
    case unknown
  }

  private var screen: Screen
  private var duplicateLocators: Set<AutomationLocator>
  private var tappedIdentifiers: [String] = []

  init(screen: Screen, duplicateLocators: Set<AutomationLocator> = []) {
    self.screen = screen
    self.duplicateLocators = duplicateLocators
  }

  func elements(matching locator: AutomationLocator) async throws -> [AutomationElement] {
    guard presentLocators().contains(locator) else { return [] }
    let count = duplicateLocators.contains(locator) ? 2 : 1
    return (0..<count).map { index in
      AutomationElement(identifier: "\(locator.value)-\(index)")
    }
  }

  func tap(_ element: AutomationElement) async throws {
    tappedIdentifiers.append(element.identifier)
    switch element.identifier {
    case "task-card-0":
      screen = .taskReady
    case "start-control-0":
      screen = .recording
    case "stop-control-0":
      screen = .completionPending
    case "discard-control-0", "close-control-0":
      screen = .home
    default:
      break
    }
  }

  func isAlive() async -> Bool { true }

  func close() async {}

  func taps() -> [String] {
    tappedIdentifiers
  }

  func currentScreen() -> Screen {
    screen
  }

  private func presentLocators() -> Set<AutomationLocator> {
    switch screen {
    case .home:
      return [TestCourse.homeProof, TestCourse.taskCard]
    case .taskReady:
      return [TestCourse.taskReadyProof, TestCourse.startControl, TestCourse.closeControl]
    case .recording:
      return [TestCourse.recordingProof, TestCourse.stopControl]
    case .completionPending:
      return [TestCourse.completionProof, TestCourse.discardControl]
    case .unknown:
      return []
    }
  }
}

private enum TestCourse {
  static let homeProof = AutomationLocator.accessibilityIdentifier("home-proof")
  static let taskReadyProof = AutomationLocator.accessibilityIdentifier("task-ready-proof")
  static let recordingProof = AutomationLocator.accessibilityIdentifier("recording-proof")
  static let completionProof = AutomationLocator.accessibilityIdentifier("completion-proof")
  static let taskCard = AutomationLocator.accessibilityIdentifier("task-card")
  static let startControl = AutomationLocator.accessibilityIdentifier("start-control")
  static let stopControl = AutomationLocator.accessibilityIdentifier("stop-control")
  static let discardControl = AutomationLocator.accessibilityIdentifier("discard-control")
  static let closeControl = AutomationLocator.accessibilityIdentifier("close-control")

  static func definition(requireOperatorAtCompletion: Bool = false) -> CaptureCourseDefinition {
    let completionDisposition: CourseTransitionDisposition =
      requireOperatorAtCompletion ? .needsOperator : .action
    let completionAction = requireOperatorAtCompletion ? nil : "discard-recording"

    return CaptureCourseDefinition(
      identifier: "test-course",
      displayName: "Test Course",
      bundleIdentifier: "dev.field-app.test",
      screenProofs: [
        CourseScreenProof(screen: .home, locator: homeProof),
        CourseScreenProof(screen: .taskReady, locator: taskReadyProof),
        CourseScreenProof(screen: .recording, locator: recordingProof),
        CourseScreenProof(screen: .completionPending, locator: completionProof),
      ],
      actions: [
        CourseActionDefinition(
          identifier: "open-task",
          impact: .navigation,
          locator: taskCard
        ),
        CourseActionDefinition(
          identifier: "close-task",
          impact: .navigation,
          locator: closeControl
        ),
        CourseActionDefinition(
          identifier: "start-recording",
          impact: .startsRecording,
          locator: startControl
        ),
        CourseActionDefinition(
          identifier: "stop-recording",
          impact: .stopsRecording,
          locator: stopControl
        ),
        CourseActionDefinition(
          identifier: "discard-recording",
          impact: .deletesRecording,
          locator: discardControl
        ),
      ],
      transitions: [
        CourseTransition(
          desiredState: .running,
          screen: .home,
          disposition: .action,
          actionIdentifier: "open-task"
        ),
        CourseTransition(
          desiredState: .running,
          screen: .taskReady,
          disposition: .action,
          actionIdentifier: "start-recording"
        ),
        CourseTransition(
          desiredState: .running,
          screen: .recording,
          disposition: .stable
        ),
        CourseTransition(
          desiredState: .running,
          screen: .completionPending,
          disposition: completionDisposition,
          actionIdentifier: completionAction
        ),
        CourseTransition(
          desiredState: .paused,
          screen: .home,
          disposition: .stable
        ),
        CourseTransition(
          desiredState: .paused,
          screen: .taskReady,
          disposition: .action,
          actionIdentifier: "close-task"
        ),
        CourseTransition(
          desiredState: .paused,
          screen: .recording,
          disposition: .action,
          actionIdentifier: "stop-recording"
        ),
        CourseTransition(
          desiredState: .paused,
          screen: .completionPending,
          disposition: completionDisposition,
          actionIdentifier: completionAction
        ),
      ]
    )
  }

  static func adapter(
    session: CourseFixtureSession,
    requireOperatorAtCompletion: Bool = false
  ) throws -> CaptureCourseAdapter {
    try CaptureCourseAdapter(
      session: session,
      course: definition(requireOperatorAtCompletion: requireOperatorAtCompletion)
    )
  }
}

final class CaptureCourseTests: XCTestCase {
  func testCourseRejectsDuplicateScreenProof() throws {
    let validCourse = TestCourse.definition()
    let invalidCourse = CaptureCourseDefinition(
      identifier: validCourse.identifier,
      displayName: validCourse.displayName,
      bundleIdentifier: validCourse.bundleIdentifier,
      screenProofs: validCourse.screenProofs + [validCourse.screenProofs[0]],
      actions: validCourse.actions,
      transitions: validCourse.transitions,
      blockers: validCourse.blockers
    )

    XCTAssertThrowsError(try invalidCourse.validate()) { error in
      XCTAssertEqual(
        error as? CaptureCourseError,
        .invalidConfiguration("each course screen must have exactly one proof")
      )
    }
  }

  func testNaturalCompletionDiscardsThenStartsNextChunk() async throws {
    let session = CourseFixtureSession(screen: .completionPending)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: try TestCourse.adapter(session: session)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let screen = await session.currentScreen()
    let taps = await session.taps()

    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .recording)
    XCTAssertEqual(
      taps,
      ["discard-control-0", "task-card-0", "start-control-0"]
    )
  }

  func testPauseStopsAndDiscardsCurrentChunk() async throws {
    let session = CourseFixtureSession(screen: .recording)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: try TestCourse.adapter(session: session)
    )

    let snapshot = await worker.reconcileUntilStable()
    let screen = await session.currentScreen()
    let taps = await session.taps()

    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .home)
    XCTAssertEqual(taps, ["stop-control-0", "discard-control-0"])
  }

  func testUnknownScreenStopsWithoutTapping() async throws {
    let session = CourseFixtureSession(screen: .unknown)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: try TestCourse.adapter(session: session)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    guard case .needsAttention = snapshot.phase else {
      return XCTFail("Unknown course screen did not stop the worker.")
    }
    XCTAssertEqual(taps, [])
  }

  func testDuplicateControlStopsBeforeTap() async throws {
    let session = CourseFixtureSession(
      screen: .taskReady,
      duplicateLocators: [TestCourse.startControl]
    )
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: try TestCourse.adapter(session: session)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    guard case .needsAttention = snapshot.phase else {
      return XCTFail("Duplicate course control did not stop the worker.")
    }
    XCTAssertEqual(taps, [])
  }

  func testCourseCanRequireOperatorAtCompletion() async throws {
    let session = CourseFixtureSession(screen: .completionPending)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: try TestCourse.adapter(
        session: session,
        requireOperatorAtCompletion: true
      )
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    XCTAssertEqual(
      snapshot.phase,
      .needsAttention("Test Course requires operator review on completionPending.")
    )
    XCTAssertEqual(taps, [])
  }
}
