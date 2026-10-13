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
  /// Every element that matches any of the selectors, read in one query from
  /// whatever is in front at the center of the screen. System screens such
  /// as Control Center count as in front, so the app under them shows none.
  func elements(matching selectors: [ElementSelector]) async throws -> [AutomationElement]
  func rect(of element: AutomationElement) async throws -> AutomationRect
  /// False while something such as a dialog covers the element.
  func isHittable(_ element: AutomationElement) async throws -> Bool
  /// Throws `AppiumAutomationError.staleElement` when the element has left
  /// the screen since it was found.
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
  func systemAlertText() async throws -> String?
  func close() async
}

public enum AppiumAutomationError: Error, LocalizedError, Sendable, Equatable {
  case invalidConfiguration(String)
  case malformedResponse(String)
  case commandFailed(String)
  case noSuchAlert
  case staleElement

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
    case .staleElement:
      return "The element is no longer on screen."
    }
  }
}

extension AppiumAutomationError: CaptureLinkError {
  public var isLinkFailure: Bool {
    switch self {
    case .commandFailed, .malformedResponse:
      return true
    case .invalidConfiguration, .noSuchAlert, .staleElement:
      return false
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
  private static let reconnectInterval = Duration.seconds(10)

  private let configuration: AppiumDeviceConfiguration
  private var sessionIdentifier: String?
  private var lastConnectionAttempt: ContinuousClock.Instant?

  private init(configuration: AppiumDeviceConfiguration) {
    self.configuration = configuration
  }

  public static func start(
    configuration: AppiumDeviceConfiguration
  ) async throws -> AppiumSession {
    let session = AppiumSession(configuration: configuration)
    _ = try await session.connectedSessionIdentifier()
    return session
  }

  public func elements(
    matching selectors: [ElementSelector]
  ) async throws -> [AutomationElement] {
    guard !selectors.isEmpty else { return [] }
    let value = try await command(
      "POST",
      ["elements"],
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
    let value = try await command("GET", ["element", element.identifier, "rect"])
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
    let value = try await command("GET", ["element", element.identifier, "attribute", "hittable"])
    return (value as? String) == "true" || (value as? Bool) == true
  }

  public func tap(_ element: AutomationElement) async throws {
    _ = try await command("POST", ["element", element.identifier, "click"], body: [:])
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

  public func scrollToTop(atX x: Double) async throws {
    _ = try await execute("mobile: tap", arguments: ["x": x, "y": 12])
  }

  public func frontmostBundleIdentifier() async throws -> String? {
    let value = try await execute("mobile: activeAppInfo", arguments: [:])
    return (value as? [String: Any])?["bundleId"] as? String
  }

  public func batteryState() async throws -> BatteryState {
    let value = try await execute("mobile: batteryInfo", arguments: [:]) as? [String: Any]
    guard let level = (value?["level"] as? NSNumber)?.doubleValue else {
      throw AppiumAutomationError.malformedResponse("battery level is missing")
    }
    // 2 is charging and 3 is full, in UIDevice.BatteryState numbering.
    let state = (value?["state"] as? NSNumber)?.intValue ?? 0
    return BatteryState(level: level, isCharging: state == 2 || state == 3)
  }

  public func isLocked() async throws -> Bool {
    let value = try await execute("mobile: isLocked", arguments: [:])
    return (value as? Bool) == true
  }

  public func unlock() async throws {
    _ = try await execute("mobile: unlock", arguments: [:])
  }

  public func activateApp() async throws {
    _ = try await execute(
      "mobile: activateApp",
      arguments: ["bundleId": configuration.bundleIdentifier]
    )
  }

  public func terminateApp() async throws {
    _ = try await execute(
      "mobile: terminateApp",
      arguments: ["bundleId": configuration.bundleIdentifier]
    )
  }

  public func systemAlertText() async throws -> String? {
    do {
      let value = try await command("GET", ["alert", "text"])
      return value as? String ?? ""
    } catch AppiumAutomationError.noSuchAlert {
      return nil
    }
  }

  public func close() async {
    await invalidateCurrentSession()
  }

  private func execute(_ script: String, arguments: [String: Any]) async throws -> Any? {
    try await command("POST", ["execute", "sync"], body: ["script": script, "args": [arguments]])
  }

  /// Sends one command within the current session. A failed command drops
  /// the session, so the next command reconnects instead of reusing a
  /// session the device may no longer have. Answers about the screen, such
  /// as a missing alert, come from a working session and keep it.
  private func command(
    _ method: String,
    _ pathComponents: [String],
    body: [String: Any]? = nil
  ) async throws -> Any? {
    let identifier = try await connectedSessionIdentifier()
    do {
      return try await request(
        method: method,
        pathComponents: ["session", identifier] + pathComponents,
        body: body
      )
    } catch let error as AppiumAutomationError where !error.isLinkFailure {
      throw error
    } catch {
      await invalidateCurrentSession()
      throw error
    }
  }

  /// Reconnects at most once per interval, so a device that stays away is
  /// retried steadily instead of in a tight loop.
  private func connectedSessionIdentifier() async throws -> String {
    if let sessionIdentifier {
      return sessionIdentifier
    }
    if let lastConnectionAttempt,
      ContinuousClock.now - lastConnectionAttempt < Self.reconnectInterval
    {
      throw AppiumAutomationError.commandFailed("waiting to reconnect to the device")
    }
    lastConnectionAttempt = .now
    try await create()
    guard let sessionIdentifier else {
      throw AppiumAutomationError.malformedResponse("sessionId is missing")
    }
    return sessionIdentifier
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
    // The session names no app, so creating or ending one never launches or
    // ends the capture app, and a recording continues across reconnects. An
    // app named here would also be read whenever it runs in the foreground,
    // even under Control Center, where a tap meant for it lands on Control
    // Center instead.
    let capabilities: [String: Any] = [
      "platformName": "iOS",
      "appium:automationName": "XCUITest",
      "appium:udid": configuration.deviceID,
      "appium:noReset": true,
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
      "appium:wdaStartupRetries": 2,
      "appium:wdaStartupRetryInterval": 10_000,
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
    // A session without its settings would read the wrong app, so it is
    // only used once they are in place.
    do {
      try await configure(identifier)
    } catch {
      _ = try? await request(method: "DELETE", pathComponents: ["session", identifier], body: nil)
      throw error
    }
    sessionIdentifier = identifier
  }

  private func configure(_ identifier: String) async throws {
    let window = try await request(
      method: "GET",
      pathComponents: ["session", identifier, "window", "rect"],
      body: nil
    )
    guard
      let window = window as? [String: Any],
      let width = (window["width"] as? NSNumber)?.doubleValue,
      let height = (window["height"] as? NSNumber)?.doubleValue
    else {
      throw AppiumAutomationError.malformedResponse("window rect is incomplete")
    }

    // Capture apps keep their main thread busy, so waiting for idle would
    // delay every tap by the full timeout. Readiness is judged from the screen.
    // WebDriverAgent treats the app under the detection point as the one in
    // front. Its default, near the top left corner, is where notification
    // banners appear, so the center of the screen is used instead.
    _ = try await request(
      method: "POST",
      pathComponents: ["session", identifier, "appium", "settings"],
      body: [
        "settings": [
          "waitForIdleTimeout": 0,
          "shouldUseCompactResponses": false,
          "elementResponseAttributes": "type,attribute/name,label",
          "activeAppDetectionPoint": "\(Int(width / 2)),\(Int(height / 2))",
        ]
      ]
    )
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
      switch errorName {
      case "no such alert":
        throw AppiumAutomationError.noSuchAlert
      case "stale element reference":
        throw AppiumAutomationError.staleElement
      default:
        let message = errorValue["message"] as? String ?? errorName
        throw AppiumAutomationError.commandFailed(message)
      }
    }
    if !(200..<300).contains(httpResponse.statusCode) {
      throw AppiumAutomationError.commandFailed("HTTP \(httpResponse.statusCode)")
    }
    return value
  }
}
