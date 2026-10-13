import XCTest

@testable import FieldAppControllerCore

private enum AdapterError: Error {
  case invalidTransition(CaptureAction, String)
}

private final class CommandLog: @unchecked Sendable {
  private let lock = NSLock()
  private var commands: [DesiredCaptureState] = []

  func append(_ command: DesiredCaptureState) {
    lock.withLock { commands.append(command) }
  }

  var all: [DesiredCaptureState] {
    lock.withLock { commands }
  }
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

  private var observation: CaptureObservation
  private var actions: [CaptureAction] = []
  private var inFlightActions = 0
  private var highestConcurrentActionCount = 0
  private let actionDelayNanoseconds: UInt64
  private var performHook: (@Sendable (CaptureAction) async -> Void)?

  init(
    screen: String = "home",
    actionDelayNanoseconds: UInt64 = 0
  ) {
    self.observation = .state(screen)
    self.actionDelayNanoseconds = actionDelayNanoseconds
  }

  init(unknown detail: String) {
    self.observation = .unknown(detail)
    self.actionDelayNanoseconds = 0
  }

  func onPerform(_ hook: @escaping @Sendable (CaptureAction) async -> Void) {
    performHook = hook
  }

  func observe(after previous: CaptureObservation?) async throws -> CaptureObservation {
    observation
  }

  func nextStep(
    toward desiredState: DesiredCaptureState,
    from observation: CaptureObservation
  ) async throws -> CaptureStep {
    let screen: String
    switch observation {
    case .state(let state):
      screen = state
    case .unknown(let detail):
      return .needsAttention(detail)
    case .systemAlert, .locked, .outsideApp:
      // This adapter's screens never leave the app.
      return .settled
    }
    switch (desiredState, screen) {
    case (.running, "home"):
      return .perform(Self.openTask)
    case (.running, "taskReady"):
      return .perform(Self.startRecording)
    case (.running, "countdown"):
      return .waitForApp
    case (.paused, "taskReady"):
      return .perform(Self.closeTask)
    case (.paused, "recording"):
      return .perform(Self.stopRecording)
    case (_, "completionPending"):
      return .perform(Self.discardRecording)
    default:
      return .settled
    }
  }

  func perform(_ action: CaptureAction, from observation: CaptureObservation) async throws {
    inFlightActions += 1
    highestConcurrentActionCount = max(highestConcurrentActionCount, inFlightActions)
    defer { inFlightActions -= 1 }

    if let performHook {
      await performHook(action)
    }
    if actionDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: actionDelayNanoseconds)
    }

    guard case .state(let screen) = self.observation else {
      throw AdapterError.invalidTransition(action, "unknown")
    }
    switch screen {
    case "home" where action == Self.openTask:
      self.observation = .state("taskReady")
    case "taskReady" where action == Self.closeTask:
      self.observation = .state("home")
    case "taskReady" where action == Self.startRecording:
      self.observation = .state("recording")
    case "recording" where action == Self.stopRecording:
      self.observation = .state("completionPending")
    case "completionPending" where action == Self.discardRecording:
      self.observation = .state("home")
    default:
      throw AdapterError.invalidTransition(action, screen)
    }

    actions.append(action)
  }

  func simulateNaturalChunkEnd() {
    observation = .state("completionPending")
  }

  func showScreen(_ screen: String) {
    observation = .state(screen)
  }

  func currentScreen() -> CaptureObservation {
    observation
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
    XCTAssertEqual(firstScreen, .state("recording"))
    XCTAssertEqual(
      firstActions,
      [InMemoryCaptureAdapter.openTask, InMemoryCaptureAdapter.startRecording]
    )

    await adapter.simulateNaturalChunkEnd()
    _ = await worker.reconcileUntilStable()

    let secondScreen = await adapter.currentScreen()
    let secondActions = await adapter.actionLog()
    XCTAssertEqual(secondScreen, .state("recording"))
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
    XCTAssertEqual(pausedScreen, .state("home"))

    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    let resumedScreen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(resumedScreen, .state("recording"))
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

  func testWorkerObservesWithoutTappingBeforeTheFirstCommand() async {
    let adapter = InMemoryCaptureAdapter(screen: "recording")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let snapshot = await worker.reconcileUntilStable()

    let actions = await adapter.actionLog()
    XCTAssertNil(snapshot.desiredState)
    XCTAssertEqual(snapshot.phase, .idle)
    XCTAssertEqual(snapshot.observation, .state("recording"))
    XCTAssertEqual(actions, [])
  }

  func testPausedWorkerLeavesTheDeviceAloneUntilTheNextCommand() async {
    let adapter = InMemoryCaptureAdapter(screen: "recording")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await worker.setDesiredState(.paused)
    _ = await worker.reconcileUntilStable()
    let actionsWhenPaused = await adapter.actionLog().count

    // A person opens a task during the break.
    await adapter.showScreen("taskReady")
    let duringBreak = await worker.reconcileUntilStable()
    let actionsDuringBreak = await adapter.actionLog().count
    XCTAssertEqual(duringBreak.observation, .state("taskReady"))
    XCTAssertEqual(actionsDuringBreak, actionsWhenPaused)

    await worker.setDesiredState(.paused)
    _ = await worker.reconcileUntilStable()
    let screen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(screen, .state("home"))
    XCTAssertEqual(actions.last, InMemoryCaptureAdapter.closeTask)
  }

  func testUnknownScreenFailsClosedWithoutTapping() async {
    let adapter = InMemoryCaptureAdapter(unknown: "The app shows a permission prompt.")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()

    XCTAssertEqual(snapshot.phase, .needsAttention("The app shows a permission prompt."))
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
    XCTAssertEqual(screen, .state("recording"))
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
    XCTAssertEqual(screen, .state("home"))
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
    XCTAssertEqual(screen, .state("home"))
    XCTAssertEqual(actions, [])
  }

  func testPauseLateInAChunkRestartStillSettles() async {
    let adapter = InMemoryCaptureAdapter(screen: "completionPending")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await adapter.onPerform { action in
      if action == InMemoryCaptureAdapter.startRecording {
        await worker.setDesiredState(.paused)
      }
    }

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable(maxTransitions: 4)

    let screen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .state("home"))
    XCTAssertEqual(
      actions,
      [
        InMemoryCaptureAdapter.discardRecording,
        InMemoryCaptureAdapter.openTask,
        InMemoryCaptureAdapter.startRecording,
        InMemoryCaptureAdapter.stopRecording,
        InMemoryCaptureAdapter.discardRecording,
      ]
    )
  }

  func testPauseAndStopEndsTheRecordingBeforeStopping() async {
    let adapter = InMemoryCaptureAdapter(screen: "recording")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await worker.setDesiredState(.running)

    let finalSnapshot = await worker.pauseAndStop()

    let screen = await adapter.currentScreen()
    let actions = await adapter.actionLog()
    XCTAssertEqual(finalSnapshot.desiredState, .paused)
    XCTAssertEqual(finalSnapshot.phase, .stable)
    XCTAssertEqual(screen, .state("home"))
    XCTAssertEqual(
      actions,
      [InMemoryCaptureAdapter.stopRecording, InMemoryCaptureAdapter.discardRecording]
    )
  }

  func testPauseAndStopWaitsForTheActionInFlight() async {
    let adapter = InMemoryCaptureAdapter(actionDelayNanoseconds: 50_000_000)
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    await worker.setDesiredState(.running)
    let polling = Task {
      await worker.reconcileUntilStable()
    }

    try? await Task.sleep(nanoseconds: 10_000_000)
    let finalSnapshot = await worker.pauseAndStop()
    _ = await polling.value

    let screen = await adapter.currentScreen()
    let maximumConcurrentActions = await adapter.maximumConcurrentActions()
    XCTAssertEqual(finalSnapshot.phase, .stable)
    XCTAssertEqual(screen, .state("home"))
    XCTAssertEqual(maximumConcurrentActions, 1)

    let actionCountAtStop = await adapter.actionLog().count
    await worker.setDesiredState(.running)
    let snapshotAfterStop = await worker.reconcileUntilStable()
    let actionCountAfterStop = await adapter.actionLog().count
    XCTAssertEqual(snapshotAfterStop.phase, .stopped)
    XCTAssertEqual(snapshotAfterStop.desiredState, .paused)
    XCTAssertEqual(actionCountAfterStop, actionCountAtStop)
  }

  func testPauseAndStopLeavesAnAttentionStateUntouched() async {
    let adapter = InMemoryCaptureAdapter(unknown: "The app shows a permission prompt.")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()

    let finalSnapshot = await worker.pauseAndStop()

    let actions = await adapter.actionLog()
    let snapshotAfterStop = await worker.snapshot()
    XCTAssertEqual(finalSnapshot.phase, .needsAttention("The app shows a permission prompt."))
    XCTAssertEqual(actions, [])
    XCTAssertEqual(snapshotAfterStop.phase, .stopped)
  }

  /// A back tap is answered as soon as the worker has the command, so a
  /// worker that is stopping has to say it did not take it.
  func testCommandIsTakenUntilTheWorkerStops() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let takenWhileRunning = await worker.setDesiredState(.running)
    _ = await worker.pauseAndStop()
    let takenAfterStopping = await worker.setDesiredState(.running)

    XCTAssertTrue(takenWhileRunning)
    XCTAssertFalse(takenAfterStopping)
  }

  /// Commands reach the worker from the terminal, the back taps, the
  /// battery guard, and the shutdown, so its report is the one place where
  /// the command can be kept for the next start.
  func testEveryChangeOfTheCommandIsReported() async {
    let adapter = InMemoryCaptureAdapter(screen: "recording")
    let reported = CommandLog()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter) { event in
      if case .desiredStateChanged(let command) = event {
        reported.append(command)
      }
    }

    await worker.setDesiredState(.running)
    await worker.setDesiredState(.running)
    _ = await worker.pauseAndStop()

    XCTAssertEqual(reported.all, [.running, .paused])
  }
}

final class BatteryGuardTests: XCTestCase {
  func testPausesOnceWhenTheLevelFallsToTheThreshold() {
    var guardian = BatteryGuard(threshold: 0.10)

    XCTAssertFalse(guardian.shouldPause(for: BatteryState(level: 0.40, isCharging: false)))
    XCTAssertTrue(guardian.shouldPause(for: BatteryState(level: 0.10, isCharging: false)))
    XCTAssertFalse(guardian.shouldPause(for: BatteryState(level: 0.08, isCharging: false)))
  }

  func testChargingDeviceIsNotPausedAndArmsTheGuardAgain() {
    var guardian = BatteryGuard(threshold: 0.10)

    XCTAssertTrue(guardian.shouldPause(for: BatteryState(level: 0.09, isCharging: false)))
    XCTAssertFalse(guardian.shouldPause(for: BatteryState(level: 0.09, isCharging: true)))
    XCTAssertTrue(guardian.shouldPause(for: BatteryState(level: 0.09, isCharging: false)))
  }
}
