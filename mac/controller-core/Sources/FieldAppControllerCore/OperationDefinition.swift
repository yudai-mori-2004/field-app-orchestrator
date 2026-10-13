import Foundation

/// What to do with a finished recording. Saving submits it to the app's
/// operator; discarding deletes it on the device.
public enum AfterRecording: String, Codable, Sendable, Equatable {
  case save
  case discard
}

/// A screen the app can show, recognized by elements that must be present
/// and elements that must be absent.
public struct DefinitionState: Codable, Sendable, Equatable {
  public let id: String
  public let present: [ElementSelector]
  public let absent: [ElementSelector]

  public init(id: String, present: [ElementSelector], absent: [ElementSelector] = []) {
    self.id = id
    self.present = present
    self.absent = absent
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case present
    case absent
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    present = try container.decode([ElementSelector].self, forKey: .present)
    absent = try container.decodeIfPresent([ElementSelector].self, forKey: .absent) ?? []
  }

  func matches(_ elements: [AutomationElement]) -> Bool {
    present.allSatisfy { selector in elements.contains(where: selector.matches) }
      && !absent.contains { selector in elements.contains(where: selector.matches) }
  }
}

/// Scrolls a list until the target appears, for targets such as a task card
/// that a virtualized list only renders near the visible area.
public struct DefinitionSearch: Codable, Sendable, Equatable {
  public let container: ElementSelector
  public let items: ElementSelector
  public let maxSwipes: Int

  public init(container: ElementSelector, items: ElementSelector, maxSwipes: Int) {
    self.container = container
    self.items = items
    self.maxSwipes = maxSwipes
  }
}

/// One tap that the app answers by moving from one of `from` to `to`.
public struct DefinitionAction: Codable, Sendable, Equatable {
  public let id: String
  public let from: [String]
  public let tap: ElementSelector
  public let search: DefinitionSearch?
  public let to: String
  public let impact: CaptureActionImpact

  public init(
    id: String,
    from: [String],
    tap: ElementSelector,
    search: DefinitionSearch? = nil,
    to: String,
    impact: CaptureActionImpact
  ) {
    self.id = id
    self.from = from
    self.tap = tap
    self.search = search
    self.to = to
    self.impact = impact
  }
}

/// A move the app makes by itself, such as a countdown ending.
public struct AppTransition: Codable, Sendable, Equatable {
  public let from: String
  public let to: String

  public init(from: String, to: String) {
    self.from = from
    self.to = to
  }
}

/// A system alert that may appear while the app is in use, recognized by
/// part of its text, and the button that closes it without changing
/// anything else.
public struct DefinitionSystemAlert: Codable, Sendable, Equatable {
  public let id: String
  public let textContains: String
  public let button: String

  public init(id: String, textContains: String, button: String) {
    self.id = id
    self.textContains = textContains
    self.button = button
  }
}

/// How to get back to known ground from a screen the definition does not
/// describe.
public struct DefinitionRecovery: Codable, Sendable, Equatable {
  /// The app is restarted unless one of these elements is on screen. They
  /// mark screens where a restart could cost work, such as a recording.
  public let relaunchUnless: [ElementSelector]

  public init(relaunchUnless: [ElementSelector]) {
    self.relaunchUnless = relaunchUnless
  }
}

public struct DefinitionGoals: Codable, Sendable, Equatable {
  public let running: [String]
  public let paused: [String]

  public init(running: [String], paused: [String]) {
    self.running = running
    self.paused = paused
  }

  func states(for desiredState: DesiredCaptureState) -> Set<String> {
    switch desiredState {
    case .running:
      return Set(running)
    case .paused:
      return Set(paused)
    }
  }
}

enum PlannedStep: Equatable {
  case settled
  case waitForApp
  case perform(DefinitionAction)
}

public struct OperationDefinition: Codable, Sendable, Equatable {
  public let identifier: String
  public let displayName: String
  public let bundleIdentifier: String
  public let afterRecording: AfterRecording
  public let states: [DefinitionState]
  public let actions: [DefinitionAction]
  public let appTransitions: [AppTransition]
  public let goals: DefinitionGoals
  public let systemAlerts: [DefinitionSystemAlert]
  public let recovery: DefinitionRecovery?

  public init(
    identifier: String,
    displayName: String,
    bundleIdentifier: String,
    afterRecording: AfterRecording,
    states: [DefinitionState],
    actions: [DefinitionAction],
    appTransitions: [AppTransition],
    goals: DefinitionGoals,
    systemAlerts: [DefinitionSystemAlert] = [],
    recovery: DefinitionRecovery? = nil
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.bundleIdentifier = bundleIdentifier
    self.afterRecording = afterRecording
    self.states = states
    self.actions = actions
    self.appTransitions = appTransitions
    self.goals = goals
    self.systemAlerts = systemAlerts
    self.recovery = recovery
  }

  private enum CodingKeys: String, CodingKey {
    case identifier
    case displayName
    case bundleIdentifier
    case afterRecording
    case states
    case actions
    case appTransitions
    case goals
    case systemAlerts
    case recovery
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    identifier = try container.decode(String.self, forKey: .identifier)
    displayName = try container.decode(String.self, forKey: .displayName)
    bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
    afterRecording = try container.decode(AfterRecording.self, forKey: .afterRecording)
    states = try container.decode([DefinitionState].self, forKey: .states)
    actions = try container.decode([DefinitionAction].self, forKey: .actions)
    appTransitions = try container.decode([AppTransition].self, forKey: .appTransitions)
    goals = try container.decode(DefinitionGoals.self, forKey: .goals)
    systemAlerts =
      try container.decodeIfPresent([DefinitionSystemAlert].self, forKey: .systemAlerts) ?? []
    recovery = try container.decodeIfPresent(DefinitionRecovery.self, forKey: .recovery)
  }

  public func validate() throws {
    let allowedIdentifierCharacters = CharacterSet.lowercaseLetters
      .union(.decimalDigits)
      .union(CharacterSet(charactersIn: "-"))
    guard
      !identifier.isEmpty,
      identifier.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
    else {
      throw OperationDefinitionError.invalidDefinition(
        "identifier must use lowercase letters, numbers, and hyphens"
      )
    }
    guard !displayName.isEmpty, !bundleIdentifier.isEmpty else {
      throw OperationDefinitionError.invalidDefinition(
        "displayName and bundleIdentifier are required"
      )
    }

    let stateIdentifiers = states.map(\.id)
    let knownStates = Set(stateIdentifiers)
    guard !states.isEmpty, knownStates.count == states.count, !knownStates.contains("") else {
      throw OperationDefinitionError.invalidDefinition("state ids must be unique and non-empty")
    }
    guard states.allSatisfy({ !$0.present.isEmpty }) else {
      throw OperationDefinitionError.invalidDefinition(
        "every state needs at least one present element"
      )
    }

    // Closing a system alert is a step like a tap, so both share one set of
    // ids.
    let actionIdentifiers = actions.map(\.id) + systemAlerts.map(\.id)
    guard Set(actionIdentifiers).count == actionIdentifiers.count, !actionIdentifiers.contains("")
    else {
      throw OperationDefinitionError.invalidDefinition(
        "action and system alert ids must be unique and non-empty"
      )
    }
    guard systemAlerts.allSatisfy({ !$0.textContains.isEmpty && !$0.button.isEmpty }) else {
      throw OperationDefinitionError.invalidDefinition(
        "every system alert needs textContains and button"
      )
    }
    for action in actions {
      guard !action.from.isEmpty, action.from.allSatisfy(knownStates.contains),
        knownStates.contains(action.to)
      else {
        throw OperationDefinitionError.invalidDefinition(
          "action \(action.id) must move between known states"
        )
      }
      if let search = action.search, !(1...100).contains(search.maxSwipes) {
        throw OperationDefinitionError.invalidDefinition(
          "action \(action.id) must search with 1 to 100 swipes"
        )
      }
    }
    guard
      appTransitions.allSatisfy({ knownStates.contains($0.from) && knownStates.contains($0.to) })
    else {
      throw OperationDefinitionError.invalidDefinition(
        "app transitions must move between known states"
      )
    }
    guard !goals.running.isEmpty, !goals.paused.isEmpty,
      (goals.running + goals.paused).allSatisfy(knownStates.contains)
    else {
      throw OperationDefinitionError.invalidDefinition(
        "running and paused goals must name known states"
      )
    }

    for selector in allSelectors {
      do {
        try selector.validate()
      } catch {
        throw OperationDefinitionError.invalidDefinition(
          "selector \(selector.value.isEmpty ? "<empty>" : selector.value) is invalid"
        )
      }
    }
    guard !allSelectors.contains(where: { $0.values.contains { $0.hasPrefix("REPLACE_WITH_") } })
    else {
      throw OperationDefinitionError.invalidDefinition(
        "replace every REPLACE_WITH_ value before running the definition"
      )
    }

    for desiredState in DesiredCaptureState.allCases {
      let distance = distances(toward: goals.states(for: desiredState))
      let stranded = stateIdentifiers.filter { distance[$0] == nil }
      guard stranded.isEmpty else {
        throw OperationDefinitionError.invalidDefinition(
          "with afterRecording \(afterRecording.rawValue), no route reaches \(desiredState.rawValue) from "
            + stranded.joined(separator: ", ")
        )
      }
    }
  }

  var proofSelectors: [ElementSelector] {
    var seen = Set<ElementSelector>()
    return states.flatMap { $0.present + $0.absent }.filter { seen.insert($0).inserted }
  }

  private var allSelectors: [ElementSelector] {
    proofSelectors
      + actions.flatMap { action in
        [action.tap] + (action.search.map { [$0.container, $0.items] } ?? [])
      }
      + (recovery?.relaunchUnless ?? [])
  }

  /// The first described alert whose text is part of `text`.
  func systemAlert(matching text: String) -> DefinitionSystemAlert? {
    systemAlerts.first { text.contains($0.textContains) }
  }

  func allows(_ impact: CaptureActionImpact) -> Bool {
    switch impact {
    case .submitsRecording:
      return afterRecording == .save
    case .deletesRecording:
      return afterRecording == .discard
    case .navigation, .startsRecording, .stopsRecording:
      return true
    }
  }

  /// Chooses the first move of the cheapest route to the goal. Waiting for
  /// the app costs more than any short route of taps, so a pause stops a
  /// recording instead of waiting for it to end.
  func nextStep(from state: String, toward desiredState: DesiredCaptureState) -> PlannedStep? {
    let goalStates = goals.states(for: desiredState)
    if goalStates.contains(state) {
      return .settled
    }

    let distance = distances(toward: goalStates)
    var best: (cost: Int, step: PlannedStep)?
    for action in actions where allows(action.impact) && action.from.contains(state) {
      guard let remaining = distance[action.to] else { continue }
      let cost = Self.cost(of: action) + remaining
      if best.map({ cost < $0.cost }) ?? true {
        best = (cost, .perform(action))
      }
    }
    for transition in appTransitions where transition.from == state {
      guard let remaining = distance[transition.to] else { continue }
      let cost = Self.waitCost + remaining
      if best.map({ cost < $0.cost }) ?? true {
        best = (cost, .waitForApp)
      }
    }
    return best?.step
  }

  private static let waitCost = 10

  private static func cost(of action: DefinitionAction) -> Int {
    action.impact == .navigation ? 1 : 2
  }

  private func distances(toward goalStates: Set<String>) -> [String: Int] {
    var edges: [(from: String, to: String, cost: Int)] = []
    for action in actions where allows(action.impact) {
      for source in action.from {
        edges.append((source, action.to, Self.cost(of: action)))
      }
    }
    for transition in appTransitions {
      edges.append((transition.from, transition.to, Self.waitCost))
    }

    var distance = Dictionary(uniqueKeysWithValues: goalStates.map { ($0, 0) })
    var changed = true
    while changed {
      changed = false
      for edge in edges {
        guard let remaining = distance[edge.to] else { continue }
        let candidate = edge.cost + remaining
        if distance[edge.from].map({ candidate < $0 }) ?? true {
          distance[edge.from] = candidate
          changed = true
        }
      }
    }
    return distance
  }
}

public enum OperationDefinitionError: Error, LocalizedError, Sendable, Equatable {
  case invalidDefinition(String)
  case expectedExactlyOneElement(action: String, found: Int)
  case unsupportedAction(String)
  case deviceLocked

  public var errorDescription: String? {
    switch self {
    case .invalidDefinition(let detail):
      return "Invalid operation definition: \(detail)"
    case .expectedExactlyOneElement(let action, let found):
      return "Action \(action) expected exactly one element; found \(found)."
    case .unsupportedAction(let identifier):
      return "The definition does not support action \(identifier)."
    case .deviceLocked:
      return "The device is locked and could not be unlocked. A person needs to unlock it."
    }
  }
}

/// The app left the screen a step was planned from, for example when a
/// button disappeared before or during its tap.
struct ScreenMovedOn: CaptureStaleStepError {}

/// Something the definition does not describe, such as a sheet the app
/// opened or an alert, covers the element an action was going to tap. The
/// elements under it stay in place, so the screen still matches the state it
/// covers.
struct TargetCovered: CaptureCoveredStepError, LocalizedError {
  let action: String
  let cover: String

  var errorDescription: String? {
    "Action \(action) found its element covered by \(cover)."
  }
}

/// Runs an operation definition on one device: reads what the device shows,
/// plans the next step toward the requested state, and carries out one step
/// at a time.
public struct OperationDefinitionAdapter: CaptureAppAdapter {
  /// What a step does on the device.
  private enum Move {
    case tap(DefinitionAction)
    case closeAlert(DefinitionSystemAlert)
    case unlock
    case activateApp
    case relaunchApp
  }

  private static let unlock = CaptureAction(identifier: "system.unlock", impact: .navigation)
  private static let activateApp = CaptureAction(
    identifier: "system.activate-app",
    impact: .navigation
  )
  private static let relaunchApp = CaptureAction(
    identifier: "system.relaunch-app",
    impact: .navigation
  )

  private let session: any AppAutomationSession
  private let definition: OperationDefinition
  private let moves: [CaptureAction: Move]
  private let pollNanoseconds: UInt64
  private let settleReads: Int
  private let actionPolls: Int

  /// `pollNanoseconds` spaces repeated reads of the screen. A new state counts
  /// as settled when two consecutive reads agree, and an action waits up to
  /// `actionPolls` reads for the screen to change.
  public init(
    session: any AppAutomationSession,
    definition: OperationDefinition,
    pollNanoseconds: UInt64 = 300_000_000,
    settleReads: Int = 6,
    actionPolls: Int = 27
  ) throws {
    try definition.validate()
    self.session = session
    self.definition = definition
    self.pollNanoseconds = pollNanoseconds
    self.settleReads = settleReads
    self.actionPolls = actionPolls

    var moves: [CaptureAction: Move] = [
      Self.unlock: .unlock,
      Self.activateApp: .activateApp,
      Self.relaunchApp: .relaunchApp,
    ]
    for action in definition.actions {
      moves[Self.step(for: action, in: definition)] = .tap(action)
    }
    for alert in definition.systemAlerts {
      moves[Self.step(for: alert, in: definition)] = .closeAlert(alert)
    }
    self.moves = moves
  }

  public func observe(after previous: CaptureObservation?) async throws -> CaptureObservation {
    try await onCurrentScreen {
      var latest = try await readState()
      if latest == previous {
        return latest
      }
      for _ in 0..<settleReads {
        try await Task.sleep(nanoseconds: pollNanoseconds)
        let current = try await readState()
        if current == latest {
          return current
        }
        latest = current
      }
      return latest
    }
  }

  public func nextStep(
    toward desiredState: DesiredCaptureState,
    from observation: CaptureObservation
  ) async throws -> CaptureStep {
    try await onCurrentScreen { try await plan(toward: desiredState, from: observation) }
  }

  public func perform(_ action: CaptureAction, from observation: CaptureObservation) async throws {
    try await onCurrentScreen { try await carryOut(action, from: observation) }
  }

  /// An element that leaves the screen while it is read or tapped means the
  /// app moved on, so the worker observes again.
  private func onCurrentScreen<Value>(_ body: () async throws -> Value) async throws -> Value {
    do {
      return try await body()
    } catch AutomationError.staleElement {
      throw ScreenMovedOn()
    }
  }

  private func plan(
    toward desiredState: DesiredCaptureState,
    from observation: CaptureObservation
  ) async throws -> CaptureStep {
    switch observation {
    case .state(let state):
      switch definition.nextStep(from: state, toward: desiredState) {
      case .settled:
        return .settled
      case .waitForApp:
        return .waitForApp
      case .perform(let action):
        return .perform(Self.step(for: action, in: definition))
      case nil:
        return .needsAttention("No allowed route leads from \(state) to \(desiredState.rawValue).")
      }
    case .systemAlert(let text):
      guard let alert = definition.systemAlert(matching: text) else {
        return .needsAttention("A system alert needs a person: \(text)")
      }
      return .perform(Self.step(for: alert, in: definition))
    case .locked:
      return .perform(Self.unlock)
    case .outsideApp:
      return .perform(Self.activateApp)
    case .unknown(let detail):
      return try await recoveryStep(for: detail)
    }
  }

  private func carryOut(_ action: CaptureAction, from observation: CaptureObservation) async throws {
    guard let move = moves[action] else {
      throw OperationDefinitionError.unsupportedAction(action.identifier)
    }
    switch move {
    case .tap(let definitionAction):
      try await tap(definitionAction)
    case .closeAlert(let alert):
      try await close(alert)
    case .unlock:
      try await unlockDevice()
    case .activateApp:
      try await session.activateApp()
    case .relaunchApp:
      try await session.terminateApp()
      try await session.activateApp()
    }

    // Capture apps can drop a tap while busy. If the screen stays put, the
    // next plan from a fresh observation decides whether to tap again.
    for _ in 0..<actionPolls {
      try await Task.sleep(nanoseconds: pollNanoseconds)
      if try await readState() != observation {
        return
      }
    }
  }

  /// Restarting the app leaves any of its screens, but loses what the screens
  /// marked in the definition hold, such as a recording.
  private func recoveryStep(for detail: String) async throws -> CaptureStep {
    guard let recovery = definition.recovery else {
      return .needsAttention(detail)
    }
    guard try await session.frontmostBundleIdentifier() == definition.bundleIdentifier else {
      throw ScreenMovedOn()
    }
    guard try await session.elements(matching: recovery.relaunchUnless).isEmpty else {
      return .needsAttention(
        "\(detail) The definition does not allow restarting the app on this screen."
      )
    }
    return .recover(Self.relaunchApp, reason: detail)
  }

  /// Reads the app's elements first, so a device on a known screen costs one
  /// query per read. The rest is asked only when no state matches.
  private func readState() async throws -> CaptureObservation {
    let elements = try await session.elements(matching: definition.proofSelectors)
    let matching = definition.states.filter { $0.matches(elements) }
    if matching.count > 1 {
      return .unknown(
        "\(definition.displayName) matches more than one state: "
          + matching.map(\.id).joined(separator: ", ")
      )
    }
    if let state = matching.first {
      return .state(state.id)
    }
    let frontmost = try await session.frontmostBundleIdentifier()
    if frontmost == definition.bundleIdentifier {
      return .unknown("\(definition.displayName) shows a screen that matches no state.")
    }
    if try await session.isLocked() {
      return .locked
    }
    if let alert = try await session.systemAlertText() {
      return .systemAlert(alert)
    }
    return .outsideApp(frontmost)
  }

  private func tap(_ action: DefinitionAction) async throws {
    // The app's elements still look tappable under a system alert, but the
    // tap would land on the alert.
    if let alert = try await session.systemAlertText() {
      throw TargetCovered(action: action.id, cover: "the alert \"\(alert)\"")
    }
    let target = try await locate(action)
    try await session.tap(try await reachable(target, for: action))
  }

  private func close(_ alert: DefinitionSystemAlert) async throws {
    do {
      try await session.tapSystemAlertButton(alert.button)
    } catch AutomationError.noSuchAlert {
      throw ScreenMovedOn()
    }
  }

  /// Unlocking only works without a passcode. With one, a person has to
  /// unlock the device, which is not a problem with the link.
  private func unlockDevice() async throws {
    try? await session.unlock()
    if try await session.isLocked() {
      throw OperationDefinitionError.deviceLocked
    }
  }

  /// A search action looks through its list, where a missing element means
  /// the task is not there. Any other missing element means the app moved on
  /// after the step was planned.
  private func locate(_ action: DefinitionAction) async throws -> AutomationElement {
    let matches: [AutomationElement]
    if let search = action.search {
      matches = try await find(action.tap, using: search)
    } else {
      matches = try await session.elements(matching: [action.tap])
      if matches.isEmpty {
        throw ScreenMovedOn()
      }
    }
    guard matches.count == 1, let target = matches.first else {
      throw OperationDefinitionError.expectedExactlyOneElement(
        action: action.id,
        found: matches.count
      )
    }
    return target
  }

  /// Scrolls to the element when it is not rendered, and brings a single
  /// match near the middle of the list before it is tapped.
  private func find(
    _ selector: ElementSelector,
    using search: DefinitionSearch
  ) async throws -> [AutomationElement] {
    var matches = try await session.elements(matching: [selector])
    if matches.isEmpty {
      matches = try await scroll(toFind: selector, using: search)
    }
    guard matches.count == 1 else {
      return matches
    }
    try await center(matches[0], within: search.container)
    return try await session.elements(matching: [selector])
  }

  /// A dialog the definition does not know can leave the elements beneath it
  /// in place. Those report themselves as not hittable, so the tap is refused
  /// rather than landing on the dialog.
  private func reachable(
    _ element: AutomationElement,
    for action: DefinitionAction
  ) async throws -> AutomationElement {
    for _ in 0..<settleReads {
      if try await session.isHittable(element) {
        return element
      }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }
    throw TargetCovered(action: action.id, cover: "a screen the definition does not describe")
  }

  /// Starts from the top of the list and works downward. Lists that ignore
  /// the status bar are still covered by the pass back upward. A list counts
  /// as ended only after two drags in a row change nothing, because the first
  /// drag after returning to the top can leave a list where it is.
  private func scroll(
    toFind selector: ElementSelector,
    using search: DefinitionSearch
  ) async throws -> [AutomationElement] {
    let frame = try await session.rect(of: try await uniqueElement(search.container))
    let lower = AutomationPoint(x: frame.midX, y: frame.y + frame.height * 0.8)
    let upper = AutomationPoint(x: frame.midX, y: frame.y + frame.height * 0.2)

    try await session.scrollToTop(atX: frame.midX)
    try await Task.sleep(nanoseconds: pollNanoseconds * 3)
    let (initialMatches, initialItems) = try await readList(selector, search)
    if !initialMatches.isEmpty {
      return initialMatches
    }

    var visibleItems = initialItems
    for (start, end) in [(lower, upper), (upper, lower)] {
      var unchangedDrags = 0
      for _ in 0..<search.maxSwipes {
        try await session.drag(from: start, to: end)
        try await Task.sleep(nanoseconds: pollNanoseconds)
        let (found, items) = try await readList(selector, search)
        if !found.isEmpty {
          return found
        }
        unchangedDrags = items == visibleItems ? unchangedDrags + 1 : 0
        if unchangedDrags == 2 {
          break
        }
        visibleItems = items
      }
    }
    return []
  }

  private func readList(
    _ selector: ElementSelector,
    _ search: DefinitionSearch
  ) async throws -> (matches: [AutomationElement], items: Set<String>) {
    let elements = try await session.elements(matching: [selector, search.items])
    return (
      elements.filter(selector.matches),
      Set(elements.filter(search.items.matches).map(\.name))
    )
  }

  /// Brings a found element near the upper middle of its list, where it is
  /// clear of footers and the edges of the screen.
  private func center(
    _ element: AutomationElement,
    within containerSelector: ElementSelector
  ) async throws {
    let frame = try await session.rect(of: try await uniqueElement(containerSelector))
    let anchor = frame.y + frame.height * 0.4
    for _ in 0..<4 {
      let offset = try await session.rect(of: element).midY - anchor
      if abs(offset) <= frame.height * 0.2 {
        return
      }
      let step = max(-frame.height * 0.35, min(frame.height * 0.35, offset))
      try await session.drag(
        from: AutomationPoint(x: frame.midX, y: anchor + step),
        to: AutomationPoint(x: frame.midX, y: anchor)
      )
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }
  }

  /// A list that is gone means the app left the screen the step was planned
  /// from.
  private func uniqueElement(_ selector: ElementSelector) async throws -> AutomationElement {
    let matches = try await session.elements(matching: [selector])
    if matches.isEmpty {
      throw ScreenMovedOn()
    }
    guard matches.count == 1, let element = matches.first else {
      throw OperationDefinitionError.expectedExactlyOneElement(
        action: selector.value,
        found: matches.count
      )
    }
    return element
  }

  private static func step(
    for action: DefinitionAction,
    in definition: OperationDefinition
  ) -> CaptureAction {
    CaptureAction(identifier: "\(definition.identifier).\(action.id)", impact: action.impact)
  }

  private static func step(
    for alert: DefinitionSystemAlert,
    in definition: OperationDefinition
  ) -> CaptureAction {
    CaptureAction(identifier: "\(definition.identifier).\(alert.id)", impact: .navigation)
  }
}
