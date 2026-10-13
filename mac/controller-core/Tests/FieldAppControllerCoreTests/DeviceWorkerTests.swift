import XCTest

@testable import FieldAppControllerCore

private enum AdapterError: Error {
  case invalidTransition(CaptureAction, String)
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

  func testOutcomeAnswersACommandOnceTheDeviceReachesTheRequestedState() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let revision = await worker.setDesiredState(.running)
    let outcome = Task { await worker.outcome(of: revision, within: .seconds(5)) }
    // Let the caller wait before the pass runs, as a Shortcut does.
    try? await Task.sleep(nanoseconds: 20_000_000)
    _ = await worker.reconcileUntilStable()

    let answered = await outcome.value
    XCTAssertEqual(answered?.phase, .stable)
    XCTAssertEqual(answered?.observation, .state("recording"))
  }

  func testOutcomeDoesNotReportTheStateFromBeforeTheCommand() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await worker.setDesiredState(.paused)
    _ = await worker.reconcileUntilStable()

    // The paused state is still stable, but no pass has looked at the device
    // for the start yet.
    let revision = await worker.setDesiredState(.running)
    let beforeAnyPass = await worker.outcome(of: revision, within: .milliseconds(50))

    XCTAssertNil(beforeAnyPass)
  }

  func testOutcomeWaitsWhileTheAppCountsDown() async {
    let adapter = InMemoryCaptureAdapter(screen: "countdown")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let revision = await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    let duringCountdown = await worker.outcome(of: revision, within: .milliseconds(50))
    XCTAssertNil(duringCountdown)

    await adapter.showScreen("recording")
    _ = await worker.reconcileUntilStable()
    let afterCountdown = await worker.outcome(of: revision, within: .milliseconds(50))
    XCTAssertEqual(afterCountdown?.phase, .stable)
    XCTAssertEqual(afterCountdown?.observation, .state("recording"))
  }

  func testOutcomeReportsADeviceThatNeedsAPerson() async {
    let adapter = InMemoryCaptureAdapter(unknown: "The app shows a permission prompt.")
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let revision = await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    let answered = await worker.outcome(of: revision, within: .milliseconds(50))

    XCTAssertEqual(answered?.phase, .needsAttention("The app shows a permission prompt."))
  }

  func testOutcomeOfAPauseDuringAnActionIsThePausedState() async {
    let adapter = InMemoryCaptureAdapter(actionDelayNanoseconds: 50_000_000)
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)

    let startRevision = await worker.setDesiredState(.running)
    let reconciliation = Task {
      await worker.reconcileUntilStable()
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    let pauseRevision = await worker.setDesiredState(.paused)
    _ = await reconciliation.value

    let pauseOutcome = await worker.outcome(of: pauseRevision, within: .milliseconds(50))
    let startOutcome = await worker.outcome(of: startRevision, within: .milliseconds(50))
    XCTAssertEqual(pauseOutcome?.phase, .stable)
    XCTAssertEqual(pauseOutcome?.desiredState, .paused)
    XCTAssertEqual(pauseOutcome?.observation, .state("home"))
    // The start was overtaken, and the state that answers it is the pause.
    XCTAssertEqual(startOutcome?.desiredState, .paused)
  }

  func testOutcomeOfACommandOvertakenByAWaitForAPersonIsThatWait() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    await adapter.onPerform { action in
      if action == InMemoryCaptureAdapter.openTask {
        await worker.setDesiredState(.paused)
      }
    }

    // The pause arrives during the pass's last tap, and the pass then stops
    // at its limit without planning from the pause. Nothing acts on the pause
    // until a person looks, so the wait answers it.
    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable(maxTransitions: 1)
    let pauseRevision = await worker.snapshot().revision
    let answered = await worker.outcome(of: pauseRevision, within: .milliseconds(50))

    XCTAssertEqual(
      answered?.phase,
      .needsAttention("The app did not reach the requested state within the transition limit.")
    )
  }

  func testOutcomeOfACommandAfterStoppingIsTheStoppedWorker() async {
    let adapter = InMemoryCaptureAdapter()
    let worker = DeviceWorker(deviceID: "test-device", adapter: adapter)
    _ = await worker.pauseAndStop()

    let revision = await worker.setDesiredState(.running)
    let answered = await worker.outcome(of: revision, within: .milliseconds(50))

    XCTAssertEqual(answered?.phase, .stopped)
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
