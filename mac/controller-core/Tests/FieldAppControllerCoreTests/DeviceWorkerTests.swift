import XCTest
@testable import FieldAppControllerCore

private enum AdapterError: Error {
  case invalidTransition(CaptureAction, CaptureScreen)
}

private actor InMemoryCaptureAdapter: CaptureAppAdapter {
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

  func perform(_ action: CaptureAction) async throws {
    inFlightActions += 1
    highestConcurrentActionCount = max(highestConcurrentActionCount, inFlightActions)
    defer { inFlightActions -= 1 }

    if actionDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: actionDelayNanoseconds)
    }

    switch (action, screen) {
    case (.openTask, .home):
      screen = .taskReady
    case (.closeTask, .taskReady):
      screen = .home
    case (.startRecording, .taskReady):
      screen = .recording
    case (.stopRecording, .recording):
      screen = .home
    default:
      throw AdapterError.invalidTransition(action, screen)
    }

    actions.append(action)
  }

  func simulateNaturalChunkEnd() {
    screen = .home
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
    XCTAssertEqual(firstActions, [.openTask, .startRecording])

    await adapter.simulateNaturalChunkEnd()
    _ = await worker.reconcileUntilStable()

    let secondScreen = await adapter.currentScreen()
    let secondActions = await adapter.actionLog()
    XCTAssertEqual(secondScreen, .recording)
    XCTAssertEqual(secondActions, [.openTask, .startRecording, .openTask, .startRecording])
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
    XCTAssertEqual(actions, [.openTask, .startRecording, .stopRecording, .openTask, .startRecording])
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
    XCTAssertEqual(actions, [.openTask, .closeTask])
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
