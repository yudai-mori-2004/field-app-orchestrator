import Foundation
import XCTest

@testable import FieldAppControllerCore

private enum FakeAppError: Error {
  case notOnScreen(String)
  case covered(String)
  case unexpectedTap(String)
}

/// Mirrors the Minute screens observed on a device: duplicated static texts,
/// buttons that stay in the tree but stop being hittable under a dialog, a
/// task list that only renders cards near the visible area, and taps the app
/// sometimes drops.
private actor FakeMinuteApp: AppAutomationSession {
  enum Screen: Equatable {
    case tasks
    case minutes
    case settings
    case card(Int)
    case armed(Int)
    case countdown(Int)
    case recording(Int)
    case tooShortDialog(Int)
    case review(Int)
    case saveDialog(Int)
    case discardDialog(Int)
    case saved(Int)
    case somethingElse
  }

  static let bundleIdentifier = "com.bakerdata.minute"
  static let assignedTask = 17
  static let taskCount = 30
  static let renderedCards = 8
  static let listFrame = AutomationRect(x: 0, y: 129, width: 375, height: 683)

  static func cardName(_ task: Int) -> String {
    String(format: "task-card-%02d", task)
  }

  static func title(_ task: Int) -> String {
    task == assignedTask ? "Food Prep" : "Task \(task)"
  }

  private(set) var screen: Screen
  private(set) var taps: [String] = []
  private(set) var saved = 0
  private(set) var discarded = 0
  private(set) var drags = 0
  private var firstRenderedCard = 0
  private var listSettlingAtTop = false
  private var frontmost: String? = FakeMinuteApp.bundleIdentifier
  private var alert: String?
  private var droppedTaps: Set<String> = []
  private var failingCalls = 0
  private var locked = false
  private var hasPasscode = false
  private var tapsWithLostAnswers: Set<String> = []
  private let clipIsShort: Bool
  private var unknownDialog = false

  init(screen: Screen, clipIsShort: Bool = false) {
    self.screen = screen
    self.clipIsShort = clipIsShort
  }

  func showUnknownDialog() {
    unknownDialog = true
  }

  /// The next calls fail the way a lost link to WebDriverAgent does.
  func loseLink(forCalls count: Int) {
    failingCalls = count
  }

  /// The tap lands, but its answer never reaches the Mac.
  func loseAnswer(toTapOn name: String) {
    tapsWithLostAnswers.insert(name)
  }

  private func failIfLinkIsDown() throws {
    if failingCalls > 0 {
      failingCalls -= 1
      throw AppiumAutomationError.commandFailed("the link to the device is down")
    }
  }

  func showOtherApp() {
    frontmost = "com.apple.springboard"
  }

  func lock(withPasscode: Bool = false) {
    locked = true
    hasPasscode = withPasscode
  }

  func unlockByHand() {
    locked = false
  }

  func showAlert(_ text: String) {
    alert = text
  }

  func dropNextTap(on name: String) {
    droppedTaps.insert(name)
  }

  func finishCountdown() {
    if case .countdown(let task) = screen {
      screen = .recording(task)
    }
  }

  func endChunk() {
    if case .recording(let task) = screen {
      screen = .review(task)
    }
  }

  func elements(matching selectors: [ElementSelector]) async throws -> [AutomationElement] {
    try failIfLinkIsDown()
    return renderedElements().filter { element in selectors.contains { $0.matches(element) } }
  }

  func rect(of element: AutomationElement) async throws -> AutomationRect {
    if element.name == "home-tasks" {
      return Self.listFrame
    }
    for task in renderedCardRange where element.name == Self.cardName(task) {
      let row = Double(task - firstRenderedCard)
      return AutomationRect(x: 16, y: 112 + row * 150, width: 343, height: 141)
    }
    return AutomationRect(x: 0, y: 0, width: 60, height: 60)
  }

  func isHittable(_ element: AutomationElement) async throws -> Bool {
    guard !unknownDialog else { return false }
    switch screen {
    case .tooShortDialog:
      return !["record-stop", "record-screen"].contains(element.name)
    case .saveDialog, .discardDialog:
      return !["record-accept", "record-delete", "record-screen"].contains(element.name)
    default:
      return true
    }
  }

  func tap(_ element: AutomationElement) async throws {
    try failIfLinkIsDown()
    guard renderedElements().contains(element) else {
      throw FakeAppError.notOnScreen(element.name)
    }
    guard try await isHittable(element) else {
      throw FakeAppError.covered(element.name)
    }
    taps.append(element.name)
    if droppedTaps.remove(element.name) != nil {
      return
    }

    switch (screen, element.name) {
    case (.tasks, "nav-minutes"), (.settings, "nav-minutes"):
      screen = .minutes
    case (.tasks, "nav-settings"), (.minutes, "nav-settings"):
      screen = .settings
    case (.minutes, "nav-index"), (.settings, "nav-index"):
      screen = .tasks
    case (.card, "record-close"):
      screen = .tasks
    case (.card(let task), "record-start-task"):
      screen = .armed(task)
    case (.armed(let task), "record-cancel"):
      screen = .card(task)
    case (.armed(let task), "record-arm"):
      screen = .countdown(task)
    case (.countdown(let task), "record-cancel"):
      screen = .armed(task)
    case (.recording(let task), "record-stop"):
      screen = clipIsShort ? .tooShortDialog(task) : .review(task)
    case (.tooShortDialog, "OK") where element.type == "XCUIElementTypeOther":
      screen = .tasks
    case (.tooShortDialog(let task), "Start over") where element.type == "XCUIElementTypeOther":
      screen = .armed(task)
    case (.review(let task), "record-accept"):
      screen = .saveDialog(task)
    case (.review(let task), "record-delete"):
      screen = .discardDialog(task)
    case (.saveDialog(let task), "Save") where element.type == "XCUIElementTypeOther":
      saved += 1
      screen = .saved(task)
    case (.discardDialog(let task), "Discard") where element.type == "XCUIElementTypeOther":
      discarded += 1
      screen = .armed(task)
    case (.saveDialog(let task), "Cancel"), (.discardDialog(let task), "Cancel"):
      screen = .review(task)
    case (.saved(let task), "record-continue"):
      screen = .armed(task)
    case (.saved, "record-new-task"):
      screen = .tasks
    case (.tasks, let name) where name.hasPrefix("task-card-"):
      screen = .card(Int(name.dropFirst("task-card-".count)) ?? -1)
    default:
      throw FakeAppError.unexpectedTap(element.name)
    }
    if tapsWithLostAnswers.remove(element.name) != nil {
      throw AppiumAutomationError.commandFailed("the answer to the tap was lost")
    }
  }

  func drag(from start: AutomationPoint, to end: AutomationPoint) async throws {
    drags += 1
    // On the device, the first drag after a return to the top moved nothing.
    if listSettlingAtTop {
      listSettlingAtTop = false
      return
    }
    let rows = max(1, Int((abs(end.y - start.y) / 150).rounded()))
    let shift = end.y < start.y ? rows : -rows
    firstRenderedCard = min(
      max(0, firstRenderedCard + shift),
      Self.taskCount - Self.renderedCards
    )
  }

  func scrollToTop() async throws {
    firstRenderedCard = 0
    listSettlingAtTop = true
  }

  func frontmostBundleIdentifier() async throws -> String? {
    locked ? "com.apple.springboard" : frontmost
  }

  func isLocked() async throws -> Bool {
    locked
  }

  func unlock() async throws {
    guard !hasPasscode else {
      throw AppiumAutomationError.commandFailed("Timed out while waiting until the screen gets unlocked")
    }
    locked = false
  }

  func activateApp() async throws {
    guard !locked else {
      throw AppiumAutomationError.commandFailed("the device is locked")
    }
    frontmost = Self.bundleIdentifier
  }

  func systemAlertText() async throws -> String? {
    alert
  }

  func close() async {}

  private var renderedCardRange: Range<Int> {
    firstRenderedCard..<min(firstRenderedCard + Self.renderedCards, Self.taskCount)
  }

  private func renderedElements() -> [AutomationElement] {
    guard frontmost == Self.bundleIdentifier, !locked else { return [] }

    func element(_ name: String, _ type: String, label: String? = nil) -> AutomationElement {
      AutomationElement(
        identifier: "\(name)#\(type)",
        name: name,
        type: "XCUIElementType\(type)",
        label: label ?? name
      )
    }
    let navigation = [
      element("nav-index", "Other"), element("nav-minutes", "Other"),
      element("nav-settings", "Other"),
    ]
    let reviewButtons = [
      element("record-screen", "Other"), element("record-accept", "Button"),
      element("record-delete", "Button"),
    ]

    switch screen {
    case .tasks:
      return [element("home-screen", "Other"), element("home-tasks", "Other")]
        + renderedCardRange.map { task in
          element(Self.cardName(task), "Other", label: "\(Self.title(task)), Do the task., Kitchen")
        } + navigation
    case .minutes:
      return [element("minutes-screen", "Other")] + navigation
    case .settings:
      return [element("settings-screen", "Other")] + navigation
    case .card(let task):
      return [
        element("record-screen", "Other"), element("record-close", "Button"),
        element("record-start-task", "Button"), element(Self.title(task), "StaticText"),
        element(Self.title(task), "StaticText"),
      ]
    case .armed:
      return [
        element("record-screen", "Other"), element("record-pre-armed", "Other"),
        element("record-arm", "Button"), element("record-cancel", "Button"),
      ]
    case .countdown:
      return [
        element("record-screen", "Other"), element("record-pending", "Button"),
        element("record-cancel", "Button"),
      ]
    case .recording(let task):
      return [
        element("record-screen", "Other"), element("record-stop", "Button"),
        element(Self.title(task), "StaticText"),
      ]
    case .tooShortDialog(let task):
      return [
        element("record-screen", "Other"), element("record-stop", "Button"),
        element(Self.title(task), "StaticText"), element("Recording too short", "StaticText"),
        element("Recording too short", "StaticText"), element("OK", "Other"),
        element("OK", "StaticText"), element("Start over", "Other"),
        element("Start over", "StaticText"),
      ]
    case .review:
      return reviewButtons
    case .saveDialog:
      return reviewButtons + [
        element("Save this Minute?", "StaticText"), element("Save this Minute?", "StaticText"),
        element("Save", "Other"), element("Save", "StaticText"), element("Cancel", "Other"),
        element("Cancel", "StaticText"),
      ]
    case .discardDialog:
      return reviewButtons + [
        element("Discard this recording?", "StaticText"), element("Discard", "Other"),
        element("Cancel", "Other"), element("Cancel", "StaticText"),
      ]
    case .saved:
      return [
        element("record-screen", "Other"), element("record-new-task", "Button"),
        element("record-continue", "Button"),
      ]
    case .somethingElse:
      return [element("something-else", "Other")]
    }
  }
}

private enum MinuteDefinition {
  static func load(
    afterRecording: AfterRecording = .discard,
    taskTitle: String = FakeMinuteApp.title(FakeMinuteApp.assignedTask)
  ) throws -> OperationDefinition {
    let text = try String(contentsOf: exampleURL("minute-app"), encoding: .utf8)
      .replacingOccurrences(of: "REPLACE_WITH_TASK_TITLE", with: taskTitle)
      .replacingOccurrences(
        of: "\"afterRecording\": \"discard\"",
        with: "\"afterRecording\": \"\(afterRecording.rawValue)\""
      )
    return try JSONDecoder().decode(OperationDefinition.self, from: Data(text.utf8))
  }

  static func exampleURL(_ app: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("apps/\(app)/definition.example.json")
  }

  static func worker(
    for app: FakeMinuteApp,
    afterRecording: AfterRecording = .discard,
    taskTitle: String = FakeMinuteApp.title(FakeMinuteApp.assignedTask)
  ) throws -> DeviceWorker {
    let adapter = try OperationDefinitionAdapter(
      session: app,
      definition: load(afterRecording: afterRecording, taskTitle: taskTitle),
      pollNanoseconds: 1_000_000,
      settleReads: 3,
      actionPolls: 3
    )
    return DeviceWorker(deviceID: "test-device", adapter: adapter)
  }
}

/// Reconciles until the worker settles, letting the fake app finish each
/// countdown the worker waits for and retrying while the link is down.
private func settle(_ worker: DeviceWorker, _ app: FakeMinuteApp) async -> DeviceWorkerSnapshot {
  var snapshot = await worker.reconcileUntilStable()
  for _ in 0..<8 {
    switch snapshot.phase {
    case .waitingForApp:
      await app.finishCountdown()
    case .reconnecting:
      break
    default:
      return snapshot
    }
    snapshot = await worker.reconcileUntilStable()
  }
  return snapshot
}

final class OperationDefinitionTests: XCTestCase {
  func testExampleDefinitionsDecodeAndAskForLocalValues() throws {
    for app in ["minute-app", "claru-app"] {
      let data = try Data(contentsOf: MinuteDefinition.exampleURL(app))
      let definition = try JSONDecoder().decode(OperationDefinition.self, from: data)
      XCTAssertThrowsError(try definition.validate()) { error in
        XCTAssertEqual(
          error as? OperationDefinitionError,
          .invalidDefinition("replace every REPLACE_WITH_ value before running the definition")
        )
      }
    }
  }

  func testDefinitionWithoutARouteIsRejected() throws {
    let complete = try MinuteDefinition.load()
    let missingConfirmation = OperationDefinition(
      identifier: complete.identifier,
      displayName: complete.displayName,
      bundleIdentifier: complete.bundleIdentifier,
      afterRecording: complete.afterRecording,
      states: complete.states,
      actions: complete.actions.filter { $0.id != "confirm-discard" },
      appTransitions: complete.appTransitions,
      goals: complete.goals
    )

    XCTAssertThrowsError(try missingConfirmation.validate()) { error in
      guard case .invalidDefinition(let detail) = error as? OperationDefinitionError else {
        return XCTFail("Unexpected error \(error)")
      }
      XCTAssertTrue(detail.contains("no route reaches running from"), detail)
      XCTAssertTrue(detail.contains("review"), detail)
    }
  }

  func testEveryKnownScreenReachesBothGoalsUnderBothPolicies() async throws {
    let task = FakeMinuteApp.assignedTask
    let starts: [FakeMinuteApp.Screen] = [
      .tasks, .minutes, .settings, .card(5), .card(task), .armed(task), .countdown(task),
      .recording(task), .tooShortDialog(task), .review(task), .saveDialog(task),
      .discardDialog(task), .saved(task),
    ]
    for afterRecording in [AfterRecording.discard, .save] {
      for start in starts {
        for (desired, goal) in [
          (DesiredCaptureState.running, FakeMinuteApp.Screen.recording(task)),
          (.paused, .card(task)),
        ] {
          let app = FakeMinuteApp(screen: start)
          let worker = try MinuteDefinition.worker(for: app, afterRecording: afterRecording)
          await worker.setDesiredState(desired)
          let snapshot = await settle(worker, app)

          let context = "\(afterRecording) from \(start) toward \(desired)"
          let screen = await app.screen
          let saved = await app.saved
          let discarded = await app.discarded
          XCTAssertEqual(snapshot.phase, .stable, context)
          XCTAssertEqual(screen, goal, context)
          XCTAssertEqual(afterRecording == .save ? discarded : saved, 0, context)
        }
      }
    }
  }

  func testRunningFromSettingsScrollsToTheAssignedTask() async throws {
    let app = FakeMinuteApp(screen: .settings)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let drags = await app.drags
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(
      taps,
      ["nav-index", "task-card-17", "record-start-task", "record-arm"]
    )
    XCTAssertGreaterThan(drags, 0)
  }

  func testCountdownWaitsForTheAppWithoutTapping() async throws {
    let app = FakeMinuteApp(screen: .countdown(FakeMinuteApp.assignedTask))
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let waiting = await worker.reconcileUntilStable()
    let tapsWhileWaiting = await app.taps
    XCTAssertEqual(waiting.phase, .waitingForApp)
    XCTAssertEqual(tapsWhileWaiting, [])

    await app.finishCountdown()
    let recording = await worker.reconcileUntilStable()
    XCTAssertEqual(recording.phase, .stable)
    XCTAssertEqual(recording.observation, .state("recording"))
  }

  func testNaturalChunkEndSavesAndStartsTheNextChunk() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    let worker = try MinuteDefinition.worker(for: app, afterRecording: .save)
    await worker.setDesiredState(.running)
    _ = await settle(worker, app)

    await app.endChunk()
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let saved = await app.saved
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-accept", "Save", "record-continue", "record-arm"])
    XCTAssertEqual(saved, 1)
    XCTAssertEqual(screen, .recording(task))
  }

  func testPauseEndsTheChunkAndTurnsTheCameraOff() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let discarded = await app.discarded
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-stop", "record-delete", "Discard", "record-cancel"])
    XCTAssertEqual(discarded, 1)
    XCTAssertEqual(screen, .card(task))
  }

  func testPauseWithinTheFirstMinuteStartsOverAndTurnsTheCameraOff() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task), clipIsShort: true)
    let worker = try MinuteDefinition.worker(for: app, afterRecording: .save)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-stop", "Start over", "record-cancel"])
    XCTAssertEqual(screen, .card(task))
  }

  func testElementCoveredByAnUnknownDialogIsNotTapped() async throws {
    let app = FakeMinuteApp(screen: .recording(FakeMinuteApp.assignedTask))
    await app.showUnknownDialog()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(
      snapshot.phase,
      .needsAttention(
        "Action stop-recording found its element covered by a screen the definition does not describe."
      )
    )
    XCTAssertEqual(taps, [])
  }

  func testSaveDialogIsCancelledWhenRecordingsAreDiscarded() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .saveDialog(task))
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    _ = await settle(worker, app)

    let taps = await app.taps
    let saved = await app.saved
    XCTAssertEqual(taps.first, "Cancel")
    XCTAssertEqual(saved, 0)
  }

  func testOtherTaskCardIsClosedBeforeOpeningTheAssignedTask() async throws {
    let app = FakeMinuteApp(screen: .card(5))
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-close", "task-card-17"])
  }

  func testAppIsBroughtBackWhenAnotherAppIsInFront() async throws {
    let app = FakeMinuteApp(screen: .tasks)
    await app.showOtherApp()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(snapshot.observation, .state("assigned-task-card"))
  }

  func testLockedDeviceIsUnlockedAndTheRecordingContinues() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    await app.lock()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(snapshot.observation, .state("recording"))
    XCTAssertEqual(taps, [])
  }

  func testLockedDeviceWithAPasscodeWaitsForAPersonAndResumesOnTheNextCommand() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    await app.lock(withPasscode: true)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let locked = await settle(worker, app)
    XCTAssertEqual(
      locked.phase,
      .needsAttention("The device is locked and could not be unlocked. A person needs to unlock it.")
    )

    await app.unlockByHand()
    await worker.setDesiredState(.running)
    let resumed = await settle(worker, app)
    XCTAssertEqual(resumed.phase, .stable)
    XCTAssertEqual(resumed.observation, .state("recording"))
  }

  func testUnknownScreenNeedsAttentionWithoutTapping() async throws {
    let app = FakeMinuteApp(screen: .somethingElse)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    guard case .needsAttention = snapshot.phase else {
      return XCTFail("An unknown screen did not stop the worker.")
    }
    XCTAssertEqual(taps, [])
  }

  func testSystemAlertStopsTheWorkerBeforeAnyTap() async throws {
    let app = FakeMinuteApp(screen: .tasks)
    await app.showAlert("Allow access to the camera?")
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(
      snapshot.phase,
      .needsAttention("A system alert needs a person: Allow access to the camera?")
    )
    XCTAssertEqual(taps, [])
  }

  func testDroppedTapIsRepeatedAfterTheScreenStaysPut() async throws {
    let app = FakeMinuteApp(screen: .armed(FakeMinuteApp.assignedTask))
    await app.dropNextTap(on: "record-arm")
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-arm", "record-arm"])
  }

  func testLostLinkIsRetriedWithoutWaitingForAPerson() async throws {
    let app = FakeMinuteApp(screen: .armed(FakeMinuteApp.assignedTask))
    await app.loseLink(forCalls: 3)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let firstAttempt = await worker.reconcileUntilStable()
    guard case .reconnecting = firstAttempt.phase else {
      return XCTFail("A lost link should be retried, not handed to a person.")
    }
    let snapshot = await settle(worker, app)

    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .recording(FakeMinuteApp.assignedTask))
  }

  func testTapWhoseAnswerWasLostIsNotRepeatedOnceTheScreenMoved() async throws {
    let app = FakeMinuteApp(screen: .armed(FakeMinuteApp.assignedTask))
    await app.loseAnswer(toTapOn: "record-arm")
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-arm"])
  }

  func testMissingTaskCardStopsAfterSearchingBothWays() async throws {
    let app = FakeMinuteApp(screen: .tasks)
    let worker = try MinuteDefinition.worker(for: app, taskTitle: "Nonexistent Task")

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let drags = await app.drags
    XCTAssertEqual(
      snapshot.phase,
      .needsAttention("Action open-assigned-task expected exactly one element; found 0.")
    )
    XCTAssertEqual(taps, [])
    XCTAssertGreaterThan(drags, FakeMinuteApp.taskCount / 2)
  }
}
