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

  public init(
    identifier: String,
    displayName: String,
    bundleIdentifier: String,
    afterRecording: AfterRecording,
    states: [DefinitionState],
    actions: [DefinitionAction],
    appTransitions: [AppTransition],
    goals: DefinitionGoals
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.bundleIdentifier = bundleIdentifier
    self.afterRecording = afterRecording
    self.states = states
    self.actions = actions
    self.appTransitions = appTransitions
    self.goals = goals
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

    let actionIdentifiers = actions.map(\.id)
    guard Set(actionIdentifiers).count == actions.count, !actionIdentifiers.contains("") else {
      throw OperationDefinitionError.invalidDefinition("action ids must be unique and non-empty")
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
  case unknownScreen(String)
  case noRoute(from: String, toward: DesiredCaptureState)
  case expectedExactlyOneElement(action: String, found: Int)
  case unsupportedAction(String)
  case systemAlert(String)
  case coveredElement(action: String)

  public var errorDescription: String? {
    switch self {
    case .invalidDefinition(let detail):
      return "Invalid operation definition: \(detail)"
    case .unknownScreen(let detail):
      return detail
    case .noRoute(let state, let desiredState):
      return "No allowed route leads from \(state) to \(desiredState.rawValue)."
    case .expectedExactlyOneElement(let action, let found):
      return "Action \(action) expected exactly one element; found \(found)."
    case .unsupportedAction(let identifier):
      return "The definition does not support action \(identifier)."
    case .systemAlert(let text):
      return "A system alert needs a person: \(text)"
    case .coveredElement(let action):
      return "Action \(action) found its element covered by a screen the definition does not describe."
    }
  }
}

/// Runs an operation definition on one device: reads which state the app is
/// in, plans the next step toward the requested state, and taps one element
/// at a time.
public struct OperationDefinitionAdapter: CaptureAppAdapter {
  static let activateApp = CaptureAction(identifier: "system.activate-app", impact: .navigation)

  private let session: any AppAutomationSession
  private let definition: OperationDefinition
  private let actionsByRuntimeAction: [CaptureAction: DefinitionAction]
  private let pollNanoseconds: UInt64
  private let settleReads: Int
  private let actionPolls: Int

  /// `pollNanoseconds` spaces repeated reads of the screen. A state counts as
  /// settled when two consecutive reads agree, and an action waits up to
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
    self.actionsByRuntimeAction = Dictionary(
      uniqueKeysWithValues: definition.actions.map { action in
        (Self.runtimeAction(for: action, in: definition), action)
      }
    )
  }

  public func observe() async throws -> CaptureObservation {
    var previous = try await readState()
    for _ in 0..<settleReads {
      try await Task.sleep(nanoseconds: pollNanoseconds)
      let current = try await readState()
      if current == previous {
        return current
      }
      previous = current
    }
    return previous
  }

  public func nextStep(
    toward desiredState: DesiredCaptureState,
    from observation: CaptureObservation
  ) async throws -> CaptureStep {
    switch observation {
    case .outsideApp:
      return .perform(Self.activateApp)
    case .unknown(let detail):
      throw OperationDefinitionError.unknownScreen(detail)
    case .state(let state):
      guard let step = definition.nextStep(from: state, toward: desiredState) else {
        throw OperationDefinitionError.noRoute(from: state, toward: desiredState)
      }
      switch step {
      case .settled:
        return .settled
      case .waitForApp:
        return .waitForApp
      case .perform(let action):
        return .perform(Self.runtimeAction(for: action, in: definition))
      }
    }
  }

  public func perform(_ action: CaptureAction, from observation: CaptureObservation) async throws {
    if action == Self.activateApp {
      try await session.activateApp()
    } else {
      guard let definitionAction = actionsByRuntimeAction[action] else {
        throw OperationDefinitionError.unsupportedAction(action.identifier)
      }
      if let alert = try await session.systemAlertText() {
        throw OperationDefinitionError.systemAlert(alert)
      }
      let target = try await locate(definitionAction)
      try await session.tap(try await reachable(target, for: definitionAction))
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

  private func readState() async throws -> CaptureObservation {
    let elements = try await session.elements(matching: definition.proofSelectors)
    let matching = definition.states.filter { $0.matches(elements) }
    if matching.count == 1, let state = matching.first {
      return .state(state.id)
    }
    if matching.count > 1 {
      return .unknown(
        "\(definition.displayName) matches more than one state: "
          + matching.map(\.id).joined(separator: ", ")
      )
    }
    let frontmost = try await session.frontmostBundleIdentifier()
    if frontmost != definition.bundleIdentifier {
      return .outsideApp(frontmost)
    }
    return .unknown("\(definition.displayName) shows a screen that matches no state.")
  }

  private func locate(_ action: DefinitionAction) async throws -> AutomationElement {
    var matches = try await session.elements(matching: [action.tap])
    if matches.isEmpty, let search = action.search {
      matches = try await scroll(toFind: action.tap, using: search)
    }
    if matches.count == 1, let search = action.search {
      try await center(matches[0], within: search.container)
      matches = try await session.elements(matching: [action.tap])
    }
    guard matches.count == 1, let target = matches.first else {
      throw OperationDefinitionError.expectedExactlyOneElement(
        action: action.id,
        found: matches.count
      )
    }
    return target
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
    throw OperationDefinitionError.coveredElement(action: action.id)
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

    try await session.scrollToTop()
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

  private func uniqueElement(_ selector: ElementSelector) async throws -> AutomationElement {
    let matches = try await session.elements(matching: [selector])
    guard matches.count == 1, let element = matches.first else {
      throw OperationDefinitionError.expectedExactlyOneElement(
        action: selector.value,
        found: matches.count
      )
    }
    return element
  }

  private static func runtimeAction(
    for action: DefinitionAction,
    in definition: OperationDefinition
  ) -> CaptureAction {
    CaptureAction(identifier: "\(definition.identifier).\(action.id)", impact: action.impact)
  }
}
