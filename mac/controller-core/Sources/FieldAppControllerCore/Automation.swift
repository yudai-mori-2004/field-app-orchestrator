import Foundation

/// Selects elements by their accessibility name, optionally narrowed by
/// element type and by the start of the label. React Native exposes `testID`
/// as the name, and text without an identifier as its own text.
public struct ElementSelector: Codable, Sendable, Equatable, Hashable {
  public let name: String?
  public let namePrefix: String?
  public let type: String?
  public let labelPrefix: String?

  public init(
    name: String? = nil,
    namePrefix: String? = nil,
    type: String? = nil,
    labelPrefix: String? = nil
  ) {
    self.name = name
    self.namePrefix = namePrefix
    self.type = type
    self.labelPrefix = labelPrefix
  }

  public static func named(_ name: String, type: String? = nil) -> Self {
    Self(name: name, type: type)
  }

  public static func prefixed(_ prefix: String, type: String? = nil) -> Self {
    Self(namePrefix: prefix, type: type)
  }

  var value: String {
    name ?? namePrefix ?? ""
  }

  var values: [String] {
    [name, namePrefix, type, labelPrefix].compactMap { $0 }
  }

  func matches(_ element: AutomationElement) -> Bool {
    if let type, element.type != "XCUIElementType\(type)" {
      return false
    }
    if let labelPrefix, !element.label.hasPrefix(labelPrefix) {
      return false
    }
    if let name {
      return element.name == name
    }
    if let namePrefix {
      return element.name.hasPrefix(namePrefix)
    }
    return false
  }

  func validate() throws {
    guard (name == nil) != (namePrefix == nil), !value.isEmpty else {
      throw AutomationError.invalidConfiguration(
        "a selector needs exactly one non-empty name or namePrefix"
      )
    }
    if let type {
      guard !type.isEmpty, type.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
        throw AutomationError.invalidConfiguration(
          "a selector type must be an element type name such as Button or Other"
        )
      }
    }
    if labelPrefix?.isEmpty == true {
      throw AutomationError.invalidConfiguration("a selector labelPrefix cannot be empty")
    }
  }

  var predicate: String {
    var conditions = [
      name.map { "name == \(Self.literal($0))" }
        ?? "name BEGINSWITH \(Self.literal(namePrefix ?? ""))"
    ]
    if let type {
      conditions.append("type == \(Self.literal("XCUIElementType\(type)"))")
    }
    if let labelPrefix {
      conditions.append("label BEGINSWITH \(Self.literal(labelPrefix))")
    }
    return "(\(conditions.joined(separator: " AND ")))"
  }

  private static func literal(_ text: String) -> String {
    let escaped = text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}

public struct AutomationElement: Sendable, Equatable, Hashable {
  public let identifier: String
  public let name: String
  public let type: String
  public let label: String

  public init(identifier: String, name: String, type: String, label: String = "") {
    self.identifier = identifier
    self.name = name
    self.type = type
    self.label = label
  }
}

public struct AutomationRect: Sendable, Equatable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var midX: Double { x + width / 2 }
  public var midY: Double { y + height / 2 }
}

public struct AutomationPoint: Sendable, Equatable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public protocol AppAutomationSession: Sendable {
  /// Every element that matches any of the selectors, read in one query from
  /// whatever is in front at the center of the screen. System screens such
  /// as Control Center count as in front, so the app under them shows none.
  func elements(matching selectors: [ElementSelector]) async throws -> [AutomationElement]
  func rect(of element: AutomationElement) async throws -> AutomationRect
  /// False while something such as a dialog covers the element.
  func isHittable(_ element: AutomationElement) async throws -> Bool
  /// Throws `AutomationError.staleElement` when the element has left the
  /// screen since it was found.
  func tap(_ element: AutomationElement) async throws
  func drag(from start: AutomationPoint, to end: AutomationPoint) async throws
  /// Taps the status bar at `x`, which iOS answers by scrolling the frontmost
  /// list back to its top. The left end is avoided because, after a switch
  /// from another app, it holds the link back to that app.
  func scrollToTop(atX x: Double) async throws
  /// The app in front at the center of the screen. The home screen and
  /// system screens such as Control Center report the system's own app.
  func frontmostBundleIdentifier() async throws -> String?
  func isLocked() async throws -> Bool
  /// Unlocks a device without a passcode.
  func unlock() async throws
  func activateApp() async throws
  func terminateApp() async throws
  /// The title and message of the open system alert, one per line, or nil.
  func systemAlertText() async throws -> String?
  /// Throws `AutomationError.noSuchAlert` when no alert is open.
  func tapSystemAlertButton(_ label: String) async throws
  func close() async
}

public enum AutomationError: Error, LocalizedError, Sendable, Equatable {
  case invalidConfiguration(String)
  /// The link to WebDriverAgent failed, or its session is gone.
  case malformedResponse(String)
  case commandFailed(String)
  /// Answers from a working session about what is on screen.
  case noSuchAlert
  case staleElement
  case refused(String)
  /// A person on the iPhone stopped the automation, for example by holding
  /// both volume buttons. WebDriverAgent still answers but refuses to act
  /// until it is started again.
  case automationStopped(String)
  /// WebDriverAgent was started several times and never answered, for
  /// example because its signature expired. The detail is Xcode's output.
  case agentDidNotStart(String)

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let detail):
      return "Invalid configuration: \(detail)"
    case .malformedResponse(let detail):
      return "Malformed WebDriverAgent response: \(detail)"
    case .commandFailed(let detail):
      return "WebDriverAgent command failed: \(detail)"
    case .noSuchAlert:
      return "No system alert is open."
    case .staleElement:
      return "The element is no longer on screen."
    case .refused(let detail):
      return "The device refused the command: \(detail)"
    case .automationStopped(let detail):
      return "The automation was stopped on the iPhone: \(detail)"
    case .agentDidNotStart(let output):
      return "WebDriverAgent did not start on the iPhone. Xcode said:\n\(output)"
    }
  }
}

extension AutomationError: CaptureLinkError {
  public var isLinkFailure: Bool {
    switch self {
    case .commandFailed, .malformedResponse, .automationStopped:
      return true
    case .invalidConfiguration, .noSuchAlert, .staleElement, .refused, .agentDidNotStart:
      return false
    }
  }
}
