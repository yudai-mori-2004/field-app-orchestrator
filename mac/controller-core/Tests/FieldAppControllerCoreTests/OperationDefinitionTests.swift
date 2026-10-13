import Foundation
import XCTest

@testable import FieldAppControllerCore

private enum FakeAppError: Error {
  case covered(String)
  case unexpectedTap(String)
}

/// Mirrors the Minute screens observed on a device: duplicated static texts,
/// buttons that stay in the tree but stop being hittable under a dialog, a
/// task list that only renders cards near the visible area, and taps the app
/// sometimes drops. Like the session, it reads only what is in front at the
/// center of the screen, so a system alert hides the app.
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
  private(set) var relaunches = 0
  private var screenAfterLaunch = Screen.tasks
  private(set) var reads = 0
  private var firstRenderedCard = 0
  private var listSettlingAtTop = false
  private var frontmost: String? = FakeMinuteApp.bundleIdentifier
  private var alert: (text: String, buttons: [String])?
  private var pendingAlert: (afterReads: Int, text: String, buttons: [String])?
  private var droppedTaps: Set<String> = []
  private var failingCalls = 0
  private var locked = false
  private var appBeforeActivation: String?
  private var pendingMove: (afterReads: Int, screen: Screen)?
  private var moveBeforeNextTap: Screen?
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

  /// The app moves to `screen` right after the given number of reads, the way
  /// a screen can still show a button for a moment while it is torn down.
  func moveOn(afterReads count: Int, to screen: Screen) {
    pendingMove = (reads + count, screen)
  }

  /// The app moves to `screen` after a button was found and before it is
  /// tapped.
  func moveOn(beforeNextTapTo screen: Screen) {
    moveBeforeNextTap = screen
  }

  /// What the app shows after a restart, for an app that keeps opening on a
  /// screen the definition does not know, such as a login page.
  func launchesInto(_ screen: Screen) {
    screenAfterLaunch = screen
  }

  func lock(withPasscode: Bool = false) {
    locked = true
    hasPasscode = withPasscode
  }

  func unlockByHand() {
    locked = false
  }

  func showAlert(_ text: String, buttons: [String] = ["OK"]) {
    alert = (text, buttons)
  }

  /// The alert opens once the screen has been read `count` more times, the
  /// way an alert can open between reading the screen and tapping it.
  func showAlert(_ text: String, buttons: [String], afterReads count: Int) {
    pendingAlert = (reads + count, text, buttons)
  }

  private func openPendingAlert() {
    if let pendingAlert, reads >= pendingAlert.afterReads {
      alert = (pendingAlert.text, pendingAlert.buttons)
      self.pendingAlert = nil
    }
  }

  var alertIsOpen: Bool {
    alert != nil
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
    openPendingAlert()
    if let pendingMove, reads >= pendingMove.afterReads {
      screen = pendingMove.screen
      self.pendingMove = nil
    }
    reads += 1
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
    if let moveBeforeNextTap {
      screen = moveBeforeNextTap
      self.moveBeforeNextTap = nil
    }
    // WebDriverAgent answers a tap on an element that has left the screen
    // with this error.
    guard renderedElements().contains(element) else {
      throw AppiumAutomationError.staleElement
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

  func scrollToTop(atX x: Double) async throws {
    // After a switch from another app, the left end of the status bar is the
    // link back to that app.
    if x < 100, let appBeforeActivation {
      frontmost = appBeforeActivation
      return
    }
    firstRenderedCard = 0
    listSettlingAtTop = true
  }

  func frontmostBundleIdentifier() async throws -> String? {
    locked || alert != nil ? "com.apple.springboard" : frontmost
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

  func terminateApp() async throws {
    relaunches += 1
    screen = screenAfterLaunch
    unknownDialog = false
    firstRenderedCard = 0
    frontmost = "com.apple.springboard"
  }

  func activateApp() async throws {
    guard !locked else {
      throw AppiumAutomationError.commandFailed("the device is locked")
    }
    if frontmost != Self.bundleIdentifier {
      appBeforeActivation = frontmost
    }
    frontmost = Self.bundleIdentifier
  }

  func systemAlertText() async throws -> String? {
    openPendingAlert()
    return alert?.text
  }

  func tapSystemAlertButton(_ label: String) async throws {
    guard let alert else {
      throw AppiumAutomationError.noSuchAlert
    }
    // WebDriverAgent refuses a label the alert does not have.
    guard alert.buttons.contains(label) else {
      throw AppiumAutomationError.refused(
        "invalid element state: Failed to find button with label '\(label)'"
      )
    }
    taps.append(label)
    self.alert = nil
  }

  func close() async {}

  private var renderedCardRange: Range<Int> {
    firstRenderedCard..<min(firstRenderedCard + Self.renderedCards, Self.taskCount)
  }

  private func renderedElements() -> [AutomationElement] {
    guard frontmost == Self.bundleIdentifier, !locked, alert == nil else { return [] }

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

/// The low-battery alert of iOS 26 in Japanese. WebDriverAgent joins its
/// title and message with a line break.
private enum LowBatteryAlert {
  static let text = "バッテリー残量低下\nバッテリー残量はあと20%です。"
  static let buttons = ["閉じる", "低電力モード"]
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

  func testSystemAlertNeedsItsOwnIdTextAndButton() throws {
    let complete = try MinuteDefinition.load()
    func definition(with alert: DefinitionSystemAlert) -> OperationDefinition {
      OperationDefinition(
        identifier: complete.identifier,
        displayName: complete.displayName,
        bundleIdentifier: complete.bundleIdentifier,
        afterRecording: complete.afterRecording,
        states: complete.states,
        actions: complete.actions,
        appTransitions: complete.appTransitions,
        goals: complete.goals,
        systemAlerts: [alert]
      )
    }

    let sharedId = definition(with: DefinitionSystemAlert(id: "start-task", textContains: "残量", button: "閉じる"))
    let noButton = definition(with: DefinitionSystemAlert(id: "close-alert", textContains: "残量", button: ""))

    XCTAssertThrowsError(try sharedId.validate()) { error in
      XCTAssertEqual(
        error as? OperationDefinitionError,
        .invalidDefinition("action and system alert ids must be unique and non-empty")
      )
    }
    XCTAssertThrowsError(try noButton.validate()) { error in
      XCTAssertEqual(
        error as? OperationDefinitionError,
        .invalidDefinition("every system alert needs textContains and button")
      )
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

  func testSettledScreenIsReadOnceAndCheckedRarely() async throws {
    let app = FakeMinuteApp(screen: .recording(FakeMinuteApp.assignedTask))
    let worker = try MinuteDefinition.worker(for: app)
    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    let readsWhenSettled = await app.reads

    _ = await worker.reconcileUntilStable()

    let readsAfterOneMoreCheck = await app.reads
    let delay = await worker.nextObservationDelay()
    XCTAssertEqual(readsAfterOneMoreCheck - readsWhenSettled, 1)
    XCTAssertEqual(delay, .seconds(10))
  }

  func testButtonThatLeftTheScreenBeforeTheTapLeadsToANewPlan() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    let worker = try MinuteDefinition.worker(for: app)
    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    // The recording screen is already gone when the stop button is looked up.
    await app.moveOn(afterReads: 1, to: .armed(task))

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-cancel"])
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

  func testRecordingLoopsThroughChunkEndsUnderEitherPolicy() async throws {
    let task = FakeMinuteApp.assignedTask
    let tapsPerChunk: [AfterRecording: [String]] = [
      .discard: ["record-delete", "Discard", "record-arm"],
      .save: ["record-accept", "Save", "record-continue", "record-arm"],
    ]
    for (afterRecording, chunkTaps) in tapsPerChunk {
      let app = FakeMinuteApp(screen: .recording(task))
      let worker = try MinuteDefinition.worker(for: app, afterRecording: afterRecording)
      await worker.setDesiredState(.running)
      _ = await settle(worker, app)

      var snapshot = await worker.snapshot()
      for _ in 0..<3 {
        await app.endChunk()
        snapshot = await settle(worker, app)
      }

      let taps = await app.taps
      let saved = await app.saved
      let discarded = await app.discarded
      let screen = await app.screen
      let context = "\(afterRecording)"
      XCTAssertEqual(snapshot.phase, .stable, context)
      XCTAssertEqual(screen, .recording(task), context)
      XCTAssertEqual(taps, Array(repeating: chunkTaps, count: 3).flatMap { $0 }, context)
      XCTAssertEqual(afterRecording == .save ? saved : discarded, 3, context)
      XCTAssertEqual(afterRecording == .save ? discarded : saved, 0, context)
    }
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

  func testButtonThatLeftTheScreenDuringTheTapLeadsToANewPlan() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    let worker = try MinuteDefinition.worker(for: app)
    await worker.setDesiredState(.running)
    _ = await worker.reconcileUntilStable()
    // The recording reaches its limit between finding the stop button and
    // tapping it.
    await app.moveOn(beforeNextTapTo: .review(task))

    await worker.setDesiredState(.paused)
    let snapshot = await worker.reconcileUntilStable()

    let taps = await app.taps
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["record-delete", "Discard", "record-cancel"])
    XCTAssertEqual(screen, .card(task))
  }

  func testButtonCoveredDuringARecordingWaitsForAPerson() async throws {
    let app = FakeMinuteApp(screen: .recording(FakeMinuteApp.assignedTask))
    await app.showUnknownDialog()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.paused)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let relaunches = await app.relaunches
    XCTAssertEqual(
      snapshot.phase,
      .needsAttention(
        "Action stop-recording found its element covered by a screen the definition does not describe."
          + " The definition does not allow restarting the app on this screen."
      )
    )
    XCTAssertEqual(taps, [])
    XCTAssertEqual(relaunches, 0)
  }

  func testSheetOverATabIsLeftByRestartingTheApp() async throws {
    let app = FakeMinuteApp(screen: .settings)
    await app.showUnknownDialog()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let relaunches = await app.relaunches
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(relaunches, 1)
    XCTAssertEqual(taps, ["task-card-17", "record-start-task", "record-arm"])
    XCTAssertEqual(screen, .recording(FakeMinuteApp.assignedTask))
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

  func testRecordingStartsAfterAnotherAppWasInFrontOfAScrolledList() async throws {
    let app = FakeMinuteApp(screen: .tasks)
    await app.showOtherApp()
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(screen, .recording(FakeMinuteApp.assignedTask))
  }

  func testUnknownPageOutsideTheRecordFlowIsLeftByRestartingTheApp() async throws {
    let app = FakeMinuteApp(screen: .somethingElse)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let relaunches = await app.relaunches
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(relaunches, 1)
    XCTAssertEqual(screen, .recording(FakeMinuteApp.assignedTask))
  }

  func testScreenStillUnknownAfterARestartWaitsForAPerson() async throws {
    let app = FakeMinuteApp(screen: .somethingElse)
    await app.launchesInto(.somethingElse)
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let relaunches = await app.relaunches
    guard case .needsAttention = snapshot.phase else {
      return XCTFail("A screen that stays unknown after a restart did not stop the worker.")
    }
    XCTAssertEqual(relaunches, 1)
  }

  func testLowBatteryAlertIsClosedAndTheRecordingContinues() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .recording(task))
    let worker = try MinuteDefinition.worker(for: app)
    await worker.setDesiredState(.running)
    _ = await settle(worker, app)
    await app.showAlert(LowBatteryAlert.text, buttons: LowBatteryAlert.buttons)

    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let alertIsOpen = await app.alertIsOpen
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["閉じる"])
    XCTAssertFalse(alertIsOpen)
    XCTAssertEqual(screen, .recording(task))
  }

  func testAlertOpeningJustBeforeATapIsClosedBeforeTheTap() async throws {
    let task = FakeMinuteApp.assignedTask
    let app = FakeMinuteApp(screen: .armed(task))
    let worker = try MinuteDefinition.worker(for: app)
    // The first read finds the camera ready and the second confirms it; the
    // alert opens right after, before the record button is tapped.
    await app.showAlert(LowBatteryAlert.text, buttons: LowBatteryAlert.buttons, afterReads: 2)

    await worker.setDesiredState(.running)
    let snapshot = await settle(worker, app)

    let taps = await app.taps
    let screen = await app.screen
    XCTAssertEqual(snapshot.phase, .stable)
    XCTAssertEqual(taps, ["閉じる", "record-arm"])
    XCTAssertEqual(screen, .recording(task))
  }

  func testDescribedAlertWithoutItsButtonWaitsForAPerson() async throws {
    let app = FakeMinuteApp(screen: .recording(FakeMinuteApp.assignedTask))
    await app.showAlert(LowBatteryAlert.text, buttons: ["OK"])
    let worker = try MinuteDefinition.worker(for: app)

    await worker.setDesiredState(.running)
    let snapshot = await worker.reconcileUntilStable()

    guard case .needsAttention(let reason) = snapshot.phase else {
      return XCTFail("A refused button press was not handed to a person: \(snapshot.phase)")
    }
    XCTAssertTrue(reason.contains("閉じる"), reason)
  }

  func testUndescribedSystemAlertWaitsForAPerson() async throws {
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
