import Foundation

public enum CourseScreen: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
  case home
  case taskReady
  case recording
  case completionPending

  var captureScreen: CaptureScreen {
    switch self {
    case .home:
      return .home
    case .taskReady:
      return .taskReady
    case .recording:
      return .recording
    case .completionPending:
      return .completionPending
    }
  }

  init?(_ screen: CaptureScreen) {
    switch screen {
    case .home:
      self = .home
    case .taskReady:
      self = .taskReady
    case .recording:
      self = .recording
    case .completionPending:
      self = .completionPending
    case .blocked:
      return nil
    }
  }
}

public struct CourseScreenProof: Codable, Sendable, Equatable {
  public let screen: CourseScreen
  public let locator: AutomationLocator

  public init(screen: CourseScreen, locator: AutomationLocator) {
    self.screen = screen
    self.locator = locator
  }
}

public struct CourseActionDefinition: Codable, Sendable, Equatable {
  public let identifier: String
  public let impact: CaptureActionImpact
  public let locator: AutomationLocator

  public init(
    identifier: String,
    impact: CaptureActionImpact,
    locator: AutomationLocator
  ) {
    self.identifier = identifier
    self.impact = impact
    self.locator = locator
  }
}

public enum CourseTransitionDisposition: String, Codable, Sendable, Equatable {
  case stable
  case action
  case needsOperator
}

public struct CourseTransition: Codable, Sendable, Equatable {
  public let desiredState: DesiredCaptureState
  public let screen: CourseScreen
  public let disposition: CourseTransitionDisposition
  public let actionIdentifier: String?

  public init(
    desiredState: DesiredCaptureState,
    screen: CourseScreen,
    disposition: CourseTransitionDisposition,
    actionIdentifier: String? = nil
  ) {
    self.desiredState = desiredState
    self.screen = screen
    self.disposition = disposition
    self.actionIdentifier = actionIdentifier
  }
}

public enum CourseBlockerKind: String, Codable, Sendable, Equatable {
  case loginRequired
  case permissionPrompt
  case warning
}

public struct CourseBlockingSelector: Codable, Sendable, Equatable {
  public let kind: CourseBlockerKind
  public let locator: AutomationLocator
  public let detail: String?

  public init(
    kind: CourseBlockerKind,
    locator: AutomationLocator,
    detail: String? = nil
  ) {
    self.kind = kind
    self.locator = locator
    self.detail = detail
  }
}

public struct CaptureCourseDefinition: Codable, Sendable, Equatable {
  public let identifier: String
  public let displayName: String
  public let bundleIdentifier: String
  public let screenProofs: [CourseScreenProof]
  public let actions: [CourseActionDefinition]
  public let transitions: [CourseTransition]
  public let blockers: [CourseBlockingSelector]

  public init(
    identifier: String,
    displayName: String,
    bundleIdentifier: String,
    screenProofs: [CourseScreenProof],
    actions: [CourseActionDefinition],
    transitions: [CourseTransition],
    blockers: [CourseBlockingSelector] = []
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.bundleIdentifier = bundleIdentifier
    self.screenProofs = screenProofs
    self.actions = actions
    self.transitions = transitions
    self.blockers = blockers
  }

  public func validate() throws {
    let allowedIdentifierCharacters = CharacterSet.lowercaseLetters
      .union(.decimalDigits)
      .union(CharacterSet(charactersIn: "-"))
    guard
      !identifier.isEmpty,
      identifier.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
    else {
      throw CaptureCourseError.invalidConfiguration(
        "course identifier must use lowercase letters, numbers, and hyphens"
      )
    }
    guard !displayName.isEmpty, !bundleIdentifier.isEmpty else {
      throw CaptureCourseError.invalidConfiguration(
        "displayName and bundleIdentifier are required"
      )
    }

    let proofScreens = screenProofs.map(\.screen)
    guard screenProofs.count == CourseScreen.allCases.count,
      Set(proofScreens).count == CourseScreen.allCases.count,
      Set(proofScreens) == Set(CourseScreen.allCases)
    else {
      throw CaptureCourseError.invalidConfiguration(
        "each course screen must have exactly one proof"
      )
    }
    guard screenProofs.allSatisfy({ !$0.locator.value.isEmpty }) else {
      throw CaptureCourseError.invalidConfiguration(
        "every screen proof needs a locator"
      )
    }

    let actionIdentifiers = actions.map(\.identifier)
    guard Set(actionIdentifiers).count == actionIdentifiers.count else {
      throw CaptureCourseError.invalidConfiguration("action identifiers must be unique")
    }
    guard actions.allSatisfy({ !$0.identifier.isEmpty && !$0.locator.value.isEmpty }) else {
      throw CaptureCourseError.invalidConfiguration(
        "every action needs an identifier and locator"
      )
    }
    guard blockers.allSatisfy({ !$0.locator.value.isEmpty }) else {
      throw CaptureCourseError.invalidConfiguration("every blocker needs a locator")
    }
    let allLocators =
      screenProofs.map(\.locator)
      + actions.map(\.locator)
      + blockers.map(\.locator)
    guard !allLocators.contains(where: { $0.value.hasPrefix("REPLACE_WITH_") }) else {
      throw CaptureCourseError.invalidConfiguration(
        "replace every REPLACE_WITH_ locator before running the course"
      )
    }

    let expectedTransitionCount =
      DesiredCaptureState.allCases.count
      * CourseScreen.allCases.count
    let transitionKeys = transitions.map {
      TransitionKey(desiredState: $0.desiredState, screen: $0.screen)
    }
    guard transitions.count == expectedTransitionCount,
      Set(transitionKeys).count == expectedTransitionCount
    else {
      throw CaptureCourseError.invalidConfiguration(
        "each desired state and screen pair must have exactly one transition"
      )
    }

    let knownActions = Set(actionIdentifiers)
    for transition in transitions {
      switch transition.disposition {
      case .action:
        guard let actionIdentifier = transition.actionIdentifier,
          knownActions.contains(actionIdentifier)
        else {
          throw CaptureCourseError.invalidConfiguration(
            "action transition references an unknown action"
          )
        }
      case .stable, .needsOperator:
        guard transition.actionIdentifier == nil else {
          throw CaptureCourseError.invalidConfiguration(
            "only action transitions may name an action"
          )
        }
      }
    }
  }
}

public enum CaptureCourseError: Error, LocalizedError, Sendable, Equatable {
  case invalidConfiguration(String)
  case unknownScreen(String)
  case expectedExactlyOneElement(action: String, found: Int)
  case unsupportedAction(String)
  case operatorRequired(course: String, screen: CourseScreen)

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let detail):
      return "Invalid capture course: \(detail)"
    case .unknownScreen(let detail):
      return detail
    case .expectedExactlyOneElement(let action, let found):
      return "Course action \(action) expected exactly one element; found \(found)."
    case .unsupportedAction(let identifier):
      return "The course does not support action \(identifier)."
    case .operatorRequired(let course, let screen):
      return "\(course) requires operator review on \(screen.rawValue)."
    }
  }
}

public struct CaptureCourseAdapter: CaptureAppAdapter {
  private let session: any AppAutomationSession
  private let course: CaptureCourseDefinition
  private let actionsByRuntimeAction: [CaptureAction: CourseActionDefinition]
  private let transitionsByKey: [TransitionKey: CourseTransition]

  public init(
    session: any AppAutomationSession,
    course: CaptureCourseDefinition
  ) throws {
    try course.validate()
    self.session = session
    self.course = course
    self.actionsByRuntimeAction = Dictionary(
      uniqueKeysWithValues: course.actions.map { definition in
        (
          CaptureAction(
            identifier: "\(course.identifier).\(definition.identifier)",
            impact: definition.impact
          ),
          definition
        )
      }
    )
    self.transitionsByKey = Dictionary(
      uniqueKeysWithValues: course.transitions.map { transition in
        (
          TransitionKey(
            desiredState: transition.desiredState,
            screen: transition.screen
          ),
          transition
        )
      }
    )
  }

  public func observe() async throws -> CaptureScreen {
    for blocker in course.blockers {
      let matches = try await session.elements(matching: blocker.locator)
      guard !matches.isEmpty else { continue }

      switch blocker.kind {
      case .loginRequired:
        return .blocked(.loginRequired)
      case .permissionPrompt:
        return .blocked(.permissionPrompt)
      case .warning:
        return .blocked(
          .warning(blocker.detail ?? "\(course.displayName) displayed a configured warning.")
        )
      }
    }

    var observedScreens: [CourseScreen] = []
    for proof in course.screenProofs {
      let matches = try await session.elements(matching: proof.locator)
      if matches.count > 1 {
        return .blocked(
          .unknownScreen(
            "\(course.displayName) screen proof \(proof.screen.rawValue) matched more than once."
          )
        )
      }
      if matches.count == 1 {
        observedScreens.append(proof.screen)
      }
    }

    guard observedScreens.count == 1, let screen = observedScreens.first else {
      return .blocked(
        .unknownScreen(
          "Expected exactly one \(course.displayName) screen; observed \(observedScreens.count)."
        )
      )
    }
    return screen.captureScreen
  }

  public func nextAction(
    desiredState: DesiredCaptureState,
    screen: CaptureScreen
  ) async throws -> CaptureAction? {
    guard let courseScreen = CourseScreen(screen) else { return nil }
    let key = TransitionKey(desiredState: desiredState, screen: courseScreen)
    guard let transition = transitionsByKey[key] else {
      throw CaptureCourseError.invalidConfiguration("a required transition is missing")
    }

    switch transition.disposition {
    case .stable:
      return nil
    case .needsOperator:
      throw CaptureCourseError.operatorRequired(
        course: course.displayName,
        screen: courseScreen
      )
    case .action:
      guard let actionIdentifier = transition.actionIdentifier,
        let definition = course.actions.first(where: { $0.identifier == actionIdentifier })
      else {
        throw CaptureCourseError.invalidConfiguration(
          "a transition references an unknown action"
        )
      }
      return CaptureAction(
        identifier: "\(course.identifier).\(definition.identifier)",
        impact: definition.impact
      )
    }
  }

  public func perform(_ action: CaptureAction) async throws {
    guard let definition = actionsByRuntimeAction[action] else {
      throw CaptureCourseError.unsupportedAction(action.identifier)
    }
    let matches = try await session.elements(matching: definition.locator)
    guard matches.count == 1, let element = matches.first else {
      throw CaptureCourseError.expectedExactlyOneElement(
        action: action.identifier,
        found: matches.count
      )
    }
    try await session.tap(element)
  }
}

private struct TransitionKey: Hashable, Sendable {
  let desiredState: DesiredCaptureState
  let screen: CourseScreen
}
