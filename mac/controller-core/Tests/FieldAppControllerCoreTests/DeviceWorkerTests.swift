import XCTest

@testable import FieldAppControllerCore

private enum AdapterError: Error {
  case invalidTransition(CaptureAction, CaptureScreen)
}

private actor InMemoryCaptureAdapter: CaptureAppAdapter {
  fileprivate static let openTask = CaptureAction(
    identifier: "test.open-task",
    impact: .navigation
  )
  fileprivate static let closeTask = CaptureAction(
    identifier: "test.close-task",
    impact: .navigation
  )
  fileprivate static let startRecording = CaptureAction(
    identifier: "test.start-recording",
    impact: .startsRecording
  )
  fileprivate static let stopRecording = CaptureAction(
    identifier: "test.stop-recording",
    impact: .stopsRecording
  )
  fileprivate static let discardRecording = CaptureAction(
    identifier: "test.discard-recording",
    impact: .deletesRecording
  )

  private var screen: CaptureScreen
  private var actions: [CaptureAction] = []
  private var inFlightActions = 0
  private var highestConcurrentActionCount = 0
  private let actionDelayNanoseconds: UInt64

  init(
    screen: CaptureScreen = .home,
    actionDelayNanoseconds: UInt64 = 0
  ) {
    self.screen = screen
    self.actionDelayNanoseconds = actionDelayNanoseconds
  }

  func observe() async throws -> CaptureScreen {
    screen
  }

  func nextAction(
    desiredState: DesiredCaptureState,
    screen: CaptureScreen
  ) async throws -> CaptureAction? {
    switch (desiredState, screen) {
    case (.running, .home):
      return Self.openTask
    case (.running, .taskReady):
      return Self.startRecording
    case (.running, .recording):
      return nil
    case (.paused, .home):
      return nil
    case (.paused, .taskReady):
      return Self.closeTask
    case (.paused, .recording):
      return Self.stopRecording
    case (_, .completionPending):
      return Self.discardRecording
    case (_, .blocked):
      return nil
    }
  }

  func perform(_ action: CaptureAction) async throws {
    inFlightActions += 1
    highestConcurrentActionCount = max(highestConcurrentActionCount, inFlightActions)
    defer { inFlightActions -= 1 }

    if actionDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: actionDelayNanoseconds)
    }

    switch screen {
    case .home where action == Self.openTask:
      screen = .taskReady
    case .taskReady where action == Self.closeTask:
      screen = .home
    case .taskReady where action == Self.startRecording:
      screen = .recording
    case .recording where action == Self.stopRecording:
      screen = .completionPending
    case .completionPending where action == Self.discardRecording:
      screen = .home
    default:
      throw AdapterError.invalidTransition(action, screen)
    }

    actions.append(action)
  }

  func simulateNaturalChunkEnd() {
    screen = .completionPending
  }

  func setScreen(_ newScreen: CaptureScreen) {
    screen = newScreen
  }

  func currentScreen() -> CaptureScreen {
    screen
  }

  func actionLog() -> [CaptureAction] {
    actions
  }

  func maximumConcurrentActions() -> Int {
    highestConcurrentActionCount
  }
}

final class DeviceWorkerTests: XCTestCase {
  func testRunningIntentRestartsAfterNaturalChunkEnd() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()

    let firstScreen = await adapter.currentScreen()
    let firstActions = await adapter.actionLog()
    XCTAssertEqual(firstScreen, .recording)
    XCTAssertEqual(
      firstActions,
      [InMemoryCaptureAdapter.openTask, InMemoryCaptureAdapter.startRecording]
    )

    await adapter.simulateNaturalChunkEnd()
    _ = await worker.reconcileUntilStable()

    let secondScreen = await adapter.currentScreen()
    let secondActions = await adapter.actionLog()
    XCTAssertEqual(secondScreen, .recording)
    XCTAssertEqual(
      secondActions,
      [
        InMemoryCaptureAdapter.openTask,
        InMemoryCaptureAdapter.startRecording,
        InMemoryCaptureAdapter.discardRecording,
        InMemoryCaptureAdapter.openTask,
        InMemoryCaptureAdapter.startRecording,
      ]
    )
  }

  func testPauseAndResumeCanBeRequestedAtAnyTime() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()

    await worker.setDesiredState(.paused)
    _ = await worker.reconcileUntilStable()
    let pausedScreen = await adapter.currentScreen()
    XCTAssertEqual(pausedScreen, .home)

    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    let resumedScreen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(resumedScreen, .recording)
    XCTAssertEqual(
      actions,
      [
        InMemoryCaptureAdapter.openTask,
        InMemoryCaptureAdapter.startRecording,
        InMemoryCaptureAdapter.stopRecording,
        InMemoryCaptureAdapter.discardRecording,
        InMemoryCaptureAdapter.openTask,
        InMemoryCaptureAdapter.startRecording,
      ]
    )
  }

  func testBlockedScreenFailsClosedWithoutTapping() async {
    let adapter = InMemoryCaptureAdapter(screen: .blocked(.permissionPrompt))
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()

    XCTAssertEqual(
      snapshot.phase,
      .needsAttention("A permission prompt requires operator review.")
    )
    let actions = await adapter.actionLog()
    XCTAssertEqual(actions, [])
  }

  func testOverlappingReconciliationNeverSendsConcurrentActions() async {
    let adapter = InMemoryCaptureAdapter(actionDelayNanoseconds: 50_000_000)
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)

    async let first = worker.reconcileUntilStable()
    async let second = worker.reconcileUntilStable()
    _ = await (first, second)

    let maximumConcurrentActions = await adapter.maximumConcurrentActions()
    let screen = await adapter.currentScreen()
    XCTAssertEqual(maximumConcurrentActions, 1)
    XCTAssertEqual(screen, .recording)
  }

  func testPauseArrivingDuringAnActionConvergesWithoutStartingRecording() async {
    let adapter = InMemoryCaptureAdapter(actionDelayNanoseconds: 50_000_000)
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    let reconciliation = Task {
      await worker.reconcileUntilStable()
    }

    try? await Task.sleep(nanoseconds: 10_000_000)
    await worker.setDesiredState(.paused)
    _ = await reconciliation.value

    let screen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(screen, .home)
    XCTAssertEqual(
      actions,
      [InMemoryCaptureAdapter.openTask, InMemoryCaptureAdapter.closeTask]
    )
  }

  func testLatestIntentWinsBeforeAnyActionIsSent() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    await worker.setDesiredState(.paused)
    _ = await worker.reconcileUntilStable()

    let screen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(screen, .home)
    XCTAssertEqual(actions, [])
  }
}
