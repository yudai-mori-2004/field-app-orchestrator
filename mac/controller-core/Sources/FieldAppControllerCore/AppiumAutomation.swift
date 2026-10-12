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
      throw AppiumAutomationError.invalidConfiguration(
        "a selector needs exactly one non-empty name or namePrefix"
      )
    }
    if let type {
      guard !type.isEmpty, type.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
        throw AppiumAutomationError.invalidConfiguration(
          "a selector type must be an element type name such as Button or Other"
        )
      }
    }
    if labelPrefix?.isEmpty == true {
      throw AppiumAutomationError.invalidConfiguration("a selector labelPrefix cannot be empty")
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
  /// Every element that matches any of the selectors, read in one query.
  func elements(matching selectors: [ElementSelector]) async throws -> [AutomationElement]
  func rect(of element: AutomationElement) async throws -> AutomationRect
  /// False while something such as a dialog covers the element.
  func isHittable(_ element: AutomationElement) async throws -> Bool
  func tap(_ element: AutomationElement) async throws
  func drag(from start: AutomationPoint, to end: AutomationPoint) async throws
  /// Taps the status bar, which iOS answers by scrolling the frontmost list
  /// back to its top.
  func scrollToTop() async throws
  func frontmostBundleIdentifier() async throws -> String?
  func activateApp() async throws
  func systemAlertText() async throws -> String?
  func close() async
}

public enum AppiumAutomationError: Error, LocalizedError, Sendable, Equatable {
  case invalidConfiguration(String)
  case malformedResponse(String)
  case commandFailed(String)
  case noSuchAlert

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let detail):
      return "Invalid Appium configuration: \(detail)"
    case .malformedResponse(let detail):
      return "Malformed Appium response: \(detail)"
    case .commandFailed(let detail):
      return "Appium command failed: \(detail)"
    case .noSuchAlert:
      return "No system alert is open."
    }
  }
}

public struct AppiumDeviceConfiguration: Sendable, Equatable {
  public let serverURL: URL
  public let deviceID: String
  public let developmentTeam: String
  public let bundleIdentifier: String
  public let wdaLocalPort: Int
  public let wdaBundleIdentifier: String

  public init(
    serverURL: URL,
    deviceID: String,
    developmentTeam: String,
    bundleIdentifier: String,
    wdaLocalPort: Int,
    wdaBundleIdentifier: String = "dev.fieldapporchestrator.WebDriverAgentRunner"
  ) throws {
    guard !deviceID.isEmpty else {
      throw AppiumAutomationError.invalidConfiguration("deviceID is empty")
    }
    guard !developmentTeam.isEmpty else {
      throw AppiumAutomationError.invalidConfiguration("developmentTeam is empty")
    }
    guard !bundleIdentifier.isEmpty else {
      throw AppiumAutomationError.invalidConfiguration("bundleIdentifier is empty")
    }
    guard (1024...64535).contains(wdaLocalPort) else {
      throw AppiumAutomationError.invalidConfiguration(
        "wdaLocalPort must be between 1024 and 64535"
      )
    }

    self.serverURL = serverURL
    self.deviceID = deviceID
    self.developmentTeam = developmentTeam
    self.bundleIdentifier = bundleIdentifier
    self.wdaLocalPort = wdaLocalPort
    self.wdaBundleIdentifier = wdaBundleIdentifier
  }
}

public actor AppiumSession: AppAutomationSession {
  private static let webDriverElementKey = "element-6066-11e4-a52e-4f735466cecf"

  private let configuration: AppiumDeviceConfiguration
  private var sessionIdentifier: String?

  private init(configuration: AppiumDeviceConfiguration) {
    self.configuration = configuration
  }

  public static func start(
    configuration: AppiumDeviceConfiguration
  ) async throws -> AppiumSession {
    let session = AppiumSession(configuration: configuration)
    try await session.create()
    return session
  }

  public func elements(
    matching selectors: [ElementSelector]
  ) async throws -> [AutomationElement] {
    do {
      return try await elementsOnce(matching: selectors)
    } catch AppiumAutomationError.commandFailed {
      await invalidateCurrentSession()
      try await create()
      return try await elementsOnce(matching: selectors)
    }
  }

  private func elementsOnce(
    matching selectors: [ElementSelector]
  ) async throws -> [AutomationElement] {
    guard !selectors.isEmpty else { return [] }
    let sessionIdentifier = try activeSessionIdentifier()
    let value = try await request(
      method: "POST",
      pathComponents: ["session", sessionIdentifier, "elements"],
      body: [
        "using": "-ios predicate string",
        "value": selectors.map(\.predicate).joined(separator: " OR "),
      ]
    )

    guard let rawElements = value as? [[String: Any]] else {
      throw AppiumAutomationError.malformedResponse("elements result is not an array")
    }
    return try rawElements.map { rawElement in
      guard let identifier = rawElement[Self.webDriverElementKey] as? String else {
        throw AppiumAutomationError.malformedResponse("element identifier is missing")
      }
      return AutomationElement(
        identifier: identifier,
        name: rawElement["attribute/name"] as? String ?? "",
        type: rawElement["type"] as? String ?? "",
        label: rawElement["label"] as? String ?? ""
      )
    }
  }

  public func rect(of element: AutomationElement) async throws -> AutomationRect {
    let sessionIdentifier = try activeSessionIdentifier()
    let value = try await request(
      method: "GET",
      pathComponents: ["session", sessionIdentifier, "element", element.identifier, "rect"],
      body: nil
    )
    guard
      let rect = value as? [String: Any],
      let x = (rect["x"] as? NSNumber)?.doubleValue,
      let y = (rect["y"] as? NSNumber)?.doubleValue,
      let width = (rect["width"] as? NSNumber)?.doubleValue,
      let height = (rect["height"] as? NSNumber)?.doubleValue
    else {
      throw AppiumAutomationError.malformedResponse("element rect is incomplete")
    }
    return AutomationRect(x: x, y: y, width: width, height: height)
  }

  public func isHittable(_ element: AutomationElement) async throws -> Bool {
    let sessionIdentifier = try activeSessionIdentifier()
    let value = try await request(
      method: "GET",
      pathComponents: [
        "session", sessionIdentifier, "element", element.identifier, "attribute", "hittable",
      ],
      body: nil
    )
    return (value as? String) == "true" || (value as? Bool) == true
  }

  public func tap(_ element: AutomationElement) async throws {
    let sessionIdentifier = try activeSessionIdentifier()
    do {
      _ = try await request(
        method: "POST",
        pathComponents: [
          "session",
          sessionIdentifier,
          "element",
          element.identifier,
          "click",
        ],
        body: [:]
      )
    } catch {
      await invalidateCurrentSession()
      throw error
    }
  }

  public func drag(from start: AutomationPoint, to end: AutomationPoint) async throws {
    _ = try await execute(
      "mobile: dragFromToForDuration",
      arguments: [
        "fromX": start.x,
        "fromY": start.y,
        "toX": end.x,
        "toY": end.y,
        "duration": 0.4,
      ]
    )
  }

  public func scrollToTop() async throws {
    _ = try await execute("mobile: tap", arguments: ["x": 60, "y": 12])
  }

  public func frontmostBundleIdentifier() async throws -> String? {
    let value = try await execute("mobile: activeAppInfo", arguments: [:])
    return (value as? [String: Any])?["bundleId"] as? String
  }

  public func activateApp() async throws {
    _ = try await execute(
      "mobile: activateApp",
      arguments: ["bundleId": configuration.bundleIdentifier]
    )
  }

  public func systemAlertText() async throws -> String? {
    let sessionIdentifier = try activeSessionIdentifier()
    do {
      let value = try await request(
        method: "GET",
        pathComponents: ["session", sessionIdentifier, "alert", "text"],
        body: nil
      )
      return value as? String ?? ""
    } catch AppiumAutomationError.noSuchAlert {
      return nil
    }
  }

  public func close() async {
    await invalidateCurrentSession()
  }

  private func execute(_ script: String, arguments: [String: Any]) async throws -> Any? {
    let sessionIdentifier = try activeSessionIdentifier()
    return try await request(
      method: "POST",
      pathComponents: ["session", sessionIdentifier, "execute", "sync"],
      body: ["script": script, "args": [arguments]]
    )
  }

  private func invalidateCurrentSession() async {
    guard let sessionIdentifier else { return }
    self.sessionIdentifier = nil
    _ = try? await request(
      method: "DELETE",
      pathComponents: ["session", sessionIdentifier],
      body: nil
    )
  }

  private func create() async throws {
    // A new session must attach to the running app. Relaunching it would end
    // a recording in progress, and sessions are recreated after disconnects.
    let capabilities: [String: Any] = [
      "platformName": "iOS",
      "appium:automationName": "XCUITest",
      "appium:udid": configuration.deviceID,
      "appium:bundleId": configuration.bundleIdentifier,
      "appium:noReset": true,
      "appium:forceAppLaunch": false,
      "appium:shouldTerminateApp": false,
      "appium:useNewWDA": false,
      "appium:xcodeOrgId": configuration.developmentTeam,
      "appium:xcodeSigningId": "Apple Development",
      "appium:updatedWDABundleId": configuration.wdaBundleIdentifier,
      "appium:allowProvisioningDeviceRegistration": true,
      "appium:derivedDataPath": "/private/tmp/field-appium-wda-\(configuration.wdaLocalPort)",
      "appium:wdaLocalPort": configuration.wdaLocalPort,
      "appium:mjpegServerPort": configuration.wdaLocalPort + 1000,
      "appium:wdaLaunchTimeout": 120_000,
      "appium:wdaConnectionTimeout": 60_000,
      "appium:wdaStartupRetries": 3,
      "appium:wdaStartupRetryInterval": 20_000,
      "appium:newCommandTimeout": 900,
    ]
    let value = try await request(
      method: "POST",
      pathComponents: ["session"],
      body: ["capabilities": ["alwaysMatch": capabilities]]
    )
    guard
      let session = value as? [String: Any],
      let identifier = session["sessionId"] as? String,
      !identifier.isEmpty
    else {
      throw AppiumAutomationError.malformedResponse("sessionId is missing")
    }
    sessionIdentifier = identifier

    // Capture apps keep their main thread busy, so waiting for idle would
    // delay every tap by the full timeout. Readiness is judged from the screen.
    _ = try await request(
      method: "POST",
      pathComponents: ["session", identifier, "appium", "settings"],
      body: [
        "settings": [
          "waitForIdleTimeout": 0,
          "shouldUseCompactResponses": false,
          "elementResponseAttributes": "type,attribute/name,label",
        ]
      ]
    )
  }

  private func activeSessionIdentifier() throws -> String {
    guard let sessionIdentifier else {
      throw AppiumAutomationError.commandFailed("the Appium session is closed")
    }
    return sessionIdentifier
  }

  private func request(
    method: String,
    pathComponents: [String],
    body: [String: Any]?
  ) async throws -> Any? {
    let url = pathComponents.reduce(configuration.serverURL) { partialURL, component in
      partialURL.appendingPathComponent(component)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw AppiumAutomationError.commandFailed(String(describing: error))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AppiumAutomationError.malformedResponse("response is not HTTP")
    }
    guard !data.isEmpty else {
      if (200..<300).contains(httpResponse.statusCode) {
        return nil
      }
      throw AppiumAutomationError.commandFailed("HTTP \(httpResponse.statusCode)")
    }

    guard
      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw AppiumAutomationError.malformedResponse("response body is not a JSON object")
    }
    let value = payload["value"]

    if let errorValue = value as? [String: Any],
      let errorName = errorValue["error"] as? String
    {
      if errorName == "no such alert" {
        throw AppiumAutomationError.noSuchAlert
      }
      let message = errorValue["message"] as? String ?? errorName
      throw AppiumAutomationError.commandFailed(message)
    }
    if !(200..<300).contains(httpResponse.statusCode) {
      throw AppiumAutomationError.commandFailed("HTTP \(httpResponse.statusCode)")
    }
    return value
  }
}
