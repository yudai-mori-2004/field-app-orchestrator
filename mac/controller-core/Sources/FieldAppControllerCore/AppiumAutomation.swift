import Foundation

public struct AutomationElement: Sendable, Equatable, Hashable {
  public let identifier: String

  public init(identifier: String) {
    self.identifier = identifier
  }
}

public struct AutomationLocator: Codable, Sendable, Equatable, Hashable {
  public enum Strategy: String, Codable, Sendable, Hashable {
    case accessibilityIdentifier
    case identifierPrefix
  }

  public let strategy: Strategy
  public let value: String

  public init(strategy: Strategy, value: String) {
    self.strategy = strategy
    self.value = value
  }

  public static func accessibilityIdentifier(_ value: String) -> Self {
    Self(strategy: .accessibilityIdentifier, value: value)
  }

  public static func identifierPrefix(_ value: String) -> Self {
    Self(strategy: .identifierPrefix, value: value)
  }
}

public protocol AppAutomationSession: Sendable {
  func elements(matching locator: AutomationLocator) async throws -> [AutomationElement]
  func tap(_ element: AutomationElement) async throws
  func isAlive() async -> Bool
  func close() async
}

public enum AppiumAutomationError: Error, LocalizedError, Sendable, Equatable {
  case invalidConfiguration(String)
  case malformedResponse(String)
  case commandFailed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let detail):
      return "Invalid Appium configuration: \(detail)"
    case .malformedResponse(let detail):
      return "Malformed Appium response: \(detail)"
    case .commandFailed(let detail):
      return "Appium command failed: \(detail)"
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
    matching locator: AutomationLocator
  ) async throws -> [AutomationElement] {
    do {
      return try await elementsOnce(matching: locator)
    } catch AppiumAutomationError.commandFailed {
      await invalidateCurrentSession()
      try await create()
      return try await elementsOnce(matching: locator)
    }
  }

  private func elementsOnce(
    matching locator: AutomationLocator
  ) async throws -> [AutomationElement] {
    let sessionIdentifier = try activeSessionIdentifier()
    let query = try Self.query(for: locator)
    let value = try await request(
      method: "POST",
      pathComponents: ["session", sessionIdentifier, "elements"],
      body: query
    )

    guard let rawElements = value as? [[String: Any]] else {
      throw AppiumAutomationError.malformedResponse("elements result is not an array")
    }

    return try rawElements.map { rawElement in
      guard let identifier = rawElement[Self.webDriverElementKey] as? String else {
        throw AppiumAutomationError.malformedResponse("element identifier is missing")
      }
      return AutomationElement(identifier: identifier)
    }
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

  public func isAlive() async -> Bool {
    guard let sessionIdentifier else { return false }
    do {
      _ = try await request(
        method: "GET",
        pathComponents: ["session", sessionIdentifier],
        body: nil
      )
      return true
    } catch {
      return false
    }
  }

  public func close() async {
    await invalidateCurrentSession()
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
    let capabilities: [String: Any] = [
      "platformName": "iOS",
      "appium:automationName": "XCUITest",
      "appium:udid": configuration.deviceID,
      "appium:bundleId": configuration.bundleIdentifier,
      "appium:noReset": true,
      "appium:forceAppLaunch": true,
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
  }

  private func activeSessionIdentifier() throws -> String {
    guard let sessionIdentifier else {
      throw AppiumAutomationError.commandFailed("the Appium session is closed")
    }
    return sessionIdentifier
  }

  private static func query(for locator: AutomationLocator) throws -> [String: Any] {
    guard !locator.value.isEmpty else {
      throw AppiumAutomationError.invalidConfiguration("an element locator is empty")
    }

    switch locator.strategy {
    case .accessibilityIdentifier:
      return ["using": "accessibility id", "value": locator.value]
    case .identifierPrefix:
      let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
      guard locator.value.unicodeScalars.allSatisfy(allowed.contains) else {
        throw AppiumAutomationError.invalidConfiguration(
          "identifier prefixes may contain only letters, numbers, dot, underscore, colon, and hyphen"
        )
      }
      return [
        "using": "-ios predicate string",
        "value": "identifier BEGINSWITH '\(locator.value)'",
      ]
    }
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

    if !(200..<300).contains(httpResponse.statusCode) {
      let message = (value as? [String: Any])?["message"] as? String
      throw AppiumAutomationError.commandFailed(
        message ?? "HTTP \(httpResponse.statusCode)"
      )
    }
    if let errorValue = value as? [String: Any],
      let errorName = errorValue["error"] as? String
    {
      let message = errorValue["message"] as? String ?? errorName
      throw AppiumAutomationError.commandFailed(message)
    }
    return value
  }
}
