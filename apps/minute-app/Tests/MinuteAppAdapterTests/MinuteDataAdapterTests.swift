import FieldAppControllerCore
import XCTest

@testable import MinuteAppAdapter

private actor MinuteFixtureSession: AppAutomationSession {
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
      return [TestConfiguration.selectors.taskCard]
    case .taskReady:
      return [
        TestConfiguration.selectors.taskReadyProof,
        TestConfiguration.selectors.startRecording,
        TestConfiguration.selectors.closeTask,
      ]
    case .recording:
      return [
        TestConfiguration.selectors.recordingProof,
        TestConfiguration.selectors.stopRecording,
      ]
    case .completionPending:
      return [
        TestConfiguration.selectors.completionPendingProof,
        TestConfiguration.selectors.discardRecording,
      ]
    case .unknown:
      return []
    }
  }
}

private enum TestConfiguration {
  static let selectors = MinuteSelectors(
    taskCard: .accessibilityIdentifier("task-card"),
    taskReadyProof: .accessibilityIdentifier("task-ready"),
    recordingProof: .accessibilityIdentifier("recording"),
    completionPendingProof: .accessibilityIdentifier("completion"),
    startRecording: .accessibilityIdentifier("start-control"),
    stopRecording: .accessibilityIdentifier("stop-control"),
    discardRecording: .accessibilityIdentifier("discard-control"),
    closeTask: .accessibilityIdentifier("close-control")
  )

  static func adapter(
    session: MinuteFixtureSession,
    policy: MinuteCompletionPolicy = .discardAfterEachChunk
  ) -> MinuteDataAdapter {
    MinuteDataAdapter(
      session: session,
      configuration: MinuteAppConfiguration(
        selectors: selectors,
        completionPolicy: policy
      )
    )
  }
}

final class MinuteDataAdapterTests: XCTestCase {
  func testNaturalCompletionDiscardsThenStartsNextChunk() async {
    let session = MinuteFixtureSession(screen: .completionPending)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: TestConfiguration.adapter(session: session)
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

  func testPauseStopsAndDiscardsCurrentChunk() async {
    let session = MinuteFixtureSession(screen: .recording)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: TestConfiguration.adapter(session: session)
    )

    let snapshot = await worker.reconcileUntilStable()
    let screen = await session.currentScreen()
    let taps = await session.taps()

    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .home)
    XCTAssertEqual(
      taps,
      ["stop-control-0", "discard-control-0"]
    )
  }

  func testUnknownScreenStopsWithoutTapping() async {
    let session = MinuteFixtureSession(screen: .unknown)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: TestConfiguration.adapter(session: session)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    guard case .needsAttention = snapshot.phase else {
      return XCTFail("Unknown Minute screen did not stop the worker.")
    }
    XCTAssertEqual(taps, [])
  }

  func testDuplicateControlStopsBeforeTap() async {
    let session = MinuteFixtureSession(
      screen: .taskReady,
      duplicateLocators: [TestConfiguration.selectors.startRecording]
    )
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: TestConfiguration.adapter(session: session)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    guard case .needsAttention = snapshot.phase else {
      return XCTFail("Duplicate Minute control did not stop the worker.")
    }
    XCTAssertEqual(taps, [])
  }

  func testOperatorPolicyNeverDiscards() async {
    let session = MinuteFixtureSession(screen: .completionPending)
    let worker = DeviceWorker(
      deviceID: "test-device",
      adapter: TestConfiguration.adapter(session: session, policy: .requireOperator)
    )

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()
    let taps = await session.taps()

    XCTAssertEqual(
      snapshot.phase,
      .needsAttention("Minute completion is waiting for operator review.")
    )
    XCTAssertEqual(taps, [])
  }
}
