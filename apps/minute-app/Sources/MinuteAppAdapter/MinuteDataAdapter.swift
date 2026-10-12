import FieldAppControllerCore
import Foundation

public enum MinuteCompletionPolicy: String, Codable, Sendable {
  case discardAfterEachChunk
  case requireOperator
}

public enum MinuteBlockerKind: String, Codable, Sendable {
  case loginRequired
  case permissionPrompt
  case warning
}

public struct MinuteBlockingSelector: Codable, Sendable, Equatable {
  public let kind: MinuteBlockerKind
  public let locator: AutomationLocator
  public let detail: String?

  public init(
    kind: MinuteBlockerKind,
    locator: AutomationLocator,
    detail: String? = nil
  ) {
    self.kind = kind
    self.locator = locator
    self.detail = detail
  }
}

public struct MinuteSelectors: Codable, Sendable, Equatable {
  public let taskCard: AutomationLocator
  public let taskReadyProof: AutomationLocator
  public let recordingProof: AutomationLocator
  public let completionPendingProof: AutomationLocator
  public let startRecording: AutomationLocator
  public let stopRecording: AutomationLocator
  public let discardRecording: AutomationLocator
  public let closeTask: AutomationLocator
  public let blockers: [MinuteBlockingSelector]

  public init(
    taskCard: AutomationLocator,
    taskReadyProof: AutomationLocator,
    recordingProof: AutomationLocator,
    completionPendingProof: AutomationLocator,
    startRecording: AutomationLocator,
    stopRecording: AutomationLocator,
    discardRecording: AutomationLocator,
    closeTask: AutomationLocator,
    blockers: [MinuteBlockingSelector] = []
  ) {
    self.taskCard = taskCard
    self.taskReadyProof = taskReadyProof
    self.recordingProof = recordingProof
    self.completionPendingProof = completionPendingProof
    self.startRecording = startRecording
    self.stopRecording = stopRecording
    self.discardRecording = discardRecording
    self.closeTask = closeTask
    self.blockers = blockers
  }
}

public struct MinuteAppConfiguration: Codable, Sendable, Equatable {
  public let selectors: MinuteSelectors
  public let completionPolicy: MinuteCompletionPolicy

  public init(
    selectors: MinuteSelectors,
    completionPolicy: MinuteCompletionPolicy
  ) {
    self.selectors = selectors
    self.completionPolicy = completionPolicy
  }
}

public enum MinuteAdapterError: Error, LocalizedError, Sendable, Equatable {
  case expectedExactlyOneElement(action: String, found: Int)
  case unsupportedAction(String)
  case completionRequiresOperator

  public var errorDescription: String? {
    switch self {
    case .expectedExactlyOneElement(let action, let found):
      return "Minute action \(action) expected exactly one element; found \(found)."
    case .unsupportedAction(let identifier):
      return "Minute does not support the action \(identifier)."
    case .completionRequiresOperator:
      return "Minute completion is waiting for operator review."
    }
  }
}

public struct MinuteDataAdapter: CaptureAppAdapter {
  public static let bundleIdentifier = "com.bakerdata.minute"

  public static let openTask = CaptureAction(
    identifier: "minute.open-task",
    impact: .navigation
  )
  public static let closeTask = CaptureAction(
    identifier: "minute.close-task",
    impact: .navigation
  )
  public static let startRecording = CaptureAction(
    identifier: "minute.start-recording",
    impact: .startsRecording
  )
  public static let stopRecording = CaptureAction(
    identifier: "minute.stop-recording",
    impact: .stopsRecording
  )
  public static let discardRecording = CaptureAction(
    identifier: "minute.discard-recording",
    impact: .deletesRecording
  )

  private let session: any AppAutomationSession
  private let configuration: MinuteAppConfiguration

  public init(
    session: any AppAutomationSession,
    configuration: MinuteAppConfiguration
  ) {
    self.session = session
    self.configuration = configuration
  }

  public func observe() async throws -> CaptureScreen {
    for blocker in configuration.selectors.blockers {
      let matches = try await session.elements(matching: blocker.locator)
      guard !matches.isEmpty else { continue }

      switch blocker.kind {
      case .loginRequired:
        return .blocked(.loginRequired)
      case .permissionPrompt:
        return .blocked(.permissionPrompt)
      case .warning:
        return .blocked(.warning(blocker.detail ?? "Minute displayed a configured warning."))
      }
    }

    let screenProofs: [(CaptureScreen, AutomationLocator, String)] = [
      (.home, configuration.selectors.taskCard, "home"),
      (.taskReady, configuration.selectors.taskReadyProof, "taskReady"),
      (.recording, configuration.selectors.recordingProof, "recording"),
      (
        .completionPending,
        configuration.selectors.completionPendingProof,
        "completionPending"
      ),
    ]
    var observedScreens: [CaptureScreen] = []

    for (screen, locator, name) in screenProofs {
      let matches = try await session.elements(matching: locator)
      if matches.count > 1 {
        return .blocked(.unknownScreen("Minute screen proof \(name) matched more than once."))
      }
      if matches.count == 1 {
        observedScreens.append(screen)
      }
    }

    guard observedScreens.count == 1, let screen = observedScreens.first else {
      return .blocked(
        .unknownScreen(
          "Expected exactly one Minute screen state; observed \(observedScreens.count)."
        )
      )
    }
    return screen
  }

  public func nextAction(
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
      switch configuration.completionPolicy {
      case .discardAfterEachChunk:
        return Self.discardRecording
      case .requireOperator:
        throw MinuteAdapterError.completionRequiresOperator
      }
    case (_, .blocked):
      return nil
    }
  }

  public func perform(_ action: CaptureAction) async throws {
    let locator: AutomationLocator
    if action == Self.openTask {
      locator = configuration.selectors.taskCard
    } else if action == Self.closeTask {
      locator = configuration.selectors.closeTask
    } else if action == Self.startRecording {
      locator = configuration.selectors.startRecording
    } else if action == Self.stopRecording {
      locator = configuration.selectors.stopRecording
    } else if action == Self.discardRecording {
      locator = configuration.selectors.discardRecording
    } else {
      throw MinuteAdapterError.unsupportedAction(action.identifier)
    }

    let matches = try await session.elements(matching: locator)
    guard matches.count == 1, let element = matches.first else {
      throw MinuteAdapterError.expectedExactlyOneElement(
        action: action.identifier,
        found: matches.count
      )
    }
    try await session.tap(element)
  }
}
