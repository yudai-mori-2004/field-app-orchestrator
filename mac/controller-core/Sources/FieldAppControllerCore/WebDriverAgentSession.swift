import Foundation

/// The iPhone a session talks to, the app it captures with, and the
/// WebDriverAgent build that runs on the iPhone.
public struct WebDriverAgentConfiguration: Sendable, Equatable {
  public let deviceID: String
  public let bundleIdentifier: String
  /// The test run file that `xcodebuild build-for-testing` wrote for
  /// WebDriverAgent.
  public let xctestrun: URL
  /// The port WebDriverAgent listens on: USE_PORT from the test run file,
  /// or 8100 without it.
  public let port: Int

  public init(deviceID: String, bundleIdentifier: String, xctestrun: URL) throws {
    guard !deviceID.isEmpty else {
      throw AutomationError.invalidConfiguration("deviceID is empty")
    }
    guard !bundleIdentifier.isEmpty else {
      throw AutomationError.invalidConfiguration("bundleIdentifier is empty")
    }
    guard
      let data = try? Data(contentsOf: xctestrun),
      let testRun = try? PropertyListSerialization.propertyList(from: data, format: nil)
    else {
      throw AutomationError.invalidConfiguration(
        "cannot read the WebDriverAgent test run at \(xctestrun.path)"
      )
    }
    self.deviceID = deviceID
    self.bundleIdentifier = bundleIdentifier
    self.xctestrun = xctestrun
    self.port = Self.listeningPort(in: testRun) ?? 8100
  }

  private static func listeningPort(in value: Any) -> Int? {
    if let dictionary = value as? [String: Any] {
      if let environment = dictionary["EnvironmentVariables"] as? [String: Any],
        let port = (environment["USE_PORT"] as? String).flatMap({ Int($0) })
      {
        return port
      }
      return dictionary.values.lazy.compactMap(listeningPort).first
    }
    if let array = value as? [Any] {
      return array.lazy.compactMap(listeningPort).first
    }
    return nil
  }
}

/// What a session needs from the Mac to reach WebDriverAgent on an iPhone.
public protocol WebDriverAgentHost: Sendable {
  /// The iPhone's address on the link Xcode keeps to it, or nil while the
  /// iPhone is out of reach, for example away from the Wi-Fi.
  func deviceAddress() async -> String?
  /// Starts WebDriverAgent on the iPhone in place of any earlier run.
  func startAgent() async throws
  /// True while the last started WebDriverAgent may still be coming up.
  func isStartingAgent() async -> Bool
  /// The end of Xcode's output from the last start, for a person to read.
  func agentOutput() async -> String
}

/// Reaches the iPhone through Xcode. `devicectl` reports the address of the
/// link Xcode keeps to the iPhone, over Wi-Fi or USB, and `xcodebuild` runs
/// WebDriverAgent on it. A run outlives field-app, so a restarted field-app
/// finds WebDriverAgent still running.
public actor XcodeWebDriverAgentHost: WebDriverAgentHost {
  /// A start took about 8 s over Wi-Fi. This leaves room for a slow link.
  private static let startupTime = Duration.seconds(90)

  private let configuration: WebDriverAgentConfiguration
  private let outputFile: URL
  private var run: (process: Process, startedAt: ContinuousClock.Instant)?

  public init(configuration: WebDriverAgentConfiguration) {
    self.configuration = configuration
    outputFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("field-app-wda-\(configuration.deviceID).log")
  }

  public func deviceAddress() async -> String? {
    let report = FileManager.default.temporaryDirectory
      .appendingPathComponent("field-app-device-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: report) }
    let status = await Self.exitStatus(
      of: "/usr/bin/xcrun",
      [
        "devicectl", "device", "info", "details", "--device", configuration.deviceID,
        "--quiet", "--json-output", report.path,
      ],
      timeout: .seconds(30)
    )
    guard
      status == 0,
      let data = try? Data(contentsOf: report),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = json["result"] as? [String: Any],
      let connection = result["connectionProperties"] as? [String: Any],
      connection["tunnelState"] as? String == "connected",
      let address = connection["tunnelIPAddress"] as? String,
      !address.isEmpty
    else {
      return nil
    }
    return address
  }

  public func startAgent() async throws {
    if let run, run.process.isRunning {
      run.process.terminate()
    }
    // A run left by an earlier field-app would keep the iPhone busy.
    _ = await Self.exitStatus(
      of: "/usr/bin/pkill",
      ["-f", "xcodebuild.*id=\(configuration.deviceID)"],
      timeout: .seconds(10)
    )

    FileManager.default.createFile(atPath: outputFile.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputFile)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "xcodebuild", "test-without-building",
      "-xctestrun", configuration.xctestrun.path,
      "-destination", "id=\(configuration.deviceID)",
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = output
    try process.run()
    run = (process, .now)
  }

  public func isStartingAgent() -> Bool {
    guard let run else { return false }
    return run.process.isRunning && ContinuousClock.now - run.startedAt < Self.startupTime
  }

  public func agentOutput() -> String {
    guard let text = try? String(contentsOf: outputFile, encoding: .utf8) else { return "" }
    return text.split(separator: "\n").suffix(12).joined(separator: "\n")
  }

  /// Runs a tool and returns its exit status, or nil when it could not
  /// start. A tool still running after `timeout` is stopped.
  private static func exitStatus(
    of path: String,
    _ arguments: [String],
    timeout: Duration
  ) async -> Int32? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    return await withCheckedContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(returning: nil)
        return
      }
      Task {
        try? await Task.sleep(for: timeout)
        if process.isRunning {
          process.terminate()
        }
      }
    }
  }
}

/// One device's connection to WebDriverAgent, which runs on the iPhone and
/// answers over the network. A failed link drops the session, and the next
/// command reconnects.
public actor WebDriverAgentSession: AppAutomationSession {
  private static let webDriverElementKey = "element-6066-11e4-a52e-4f735466cecf"
  /// Starts in a row that WebDriverAgent never answered before a person is
  /// asked to look, for example at an expired signature.
  private static let startAttempts = 3

  private let configuration: WebDriverAgentConfiguration
  private let host: any WebDriverAgentHost
  private let reconnectInterval: Duration
  private var agent: URL?
  private var sessionIdentifier: String?
  private var connection: Task<String, Error>?
  private var lastConnectionAttempt: ContinuousClock.Instant?
  private var unansweredStarts = 0

  public init(
    configuration: WebDriverAgentConfiguration,
    host: any WebDriverAgentHost,
    reconnectInterval: Duration = .seconds(10)
  ) {
    self.configuration = configuration
    self.host = host
    self.reconnectInterval = reconnectInterval
  }

  public func elements(
    matching selectors: [ElementSelector]
  ) async throws -> [AutomationElement] {
    guard !selectors.isEmpty else { return [] }
    let value = try await command(
      "POST",
      ["elements"],
      body: [
        "using": "predicate string",
        "value": selectors.map(\.predicate).joined(separator: " OR "),
      ]
    )

    guard let rawElements = value as? [[String: Any]] else {
      throw AutomationError.malformedResponse("elements result is not an array")
    }
    return try rawElements.map { rawElement in
      guard let identifier = rawElement[Self.webDriverElementKey] as? String else {
        throw AutomationError.malformedResponse("element identifier is missing")
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
      throw AutomationError.malformedResponse("element rect is incomplete")
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
    _ = try await command(
      "POST",
      ["wda", "dragfromtoforduration"],
      body: ["fromX": start.x, "fromY": start.y, "toX": end.x, "toY": end.y, "duration": 0.4]
    )
  }

  public func scrollToTop(atX x: Double) async throws {
    _ = try await command("POST", ["wda", "tap"], body: ["x": x, "y": 12])
  }

  public func frontmostBundleIdentifier() async throws -> String? {
    let value = try await command("GET", ["wda", "activeAppInfo"])
    return (value as? [String: Any])?["bundleId"] as? String
  }

  public func batteryState() async throws -> BatteryState {
    let value = try await command("GET", ["wda", "batteryInfo"]) as? [String: Any]
    guard let level = (value?["level"] as? NSNumber)?.doubleValue else {
      throw AutomationError.malformedResponse("battery level is missing")
    }
    // 2 is charging and 3 is full, in UIDevice.BatteryState numbering.
    let state = (value?["state"] as? NSNumber)?.intValue ?? 0
    return BatteryState(level: level, isCharging: state == 2 || state == 3)
  }

  public func isLocked() async throws -> Bool {
    let value = try await command("GET", ["wda", "locked"])
    return (value as? Bool) == true
  }

  public func unlock() async throws {
    _ = try await command("POST", ["wda", "unlock"], body: [:])
  }

  public func activateApp() async throws {
    _ = try await command(
      "POST",
      ["wda", "apps", "activate"],
      body: ["bundleId": configuration.bundleIdentifier]
    )
  }

  public func terminateApp() async throws {
    _ = try await command(
      "POST",
      ["wda", "apps", "terminate"],
      body: ["bundleId": configuration.bundleIdentifier]
    )
  }

  public func systemAlertText() async throws -> String? {
    do {
      let value = try await command("GET", ["alert", "text"])
      return value as? String ?? ""
    } catch AutomationError.noSuchAlert {
      return nil
    }
  }

  public func tapSystemAlertButton(_ label: String) async throws {
    _ = try await command("POST", ["alert", "accept"], body: ["name": label])
  }

  /// Ends the session and leaves WebDriverAgent running for the next one.
  public func close() async {
    await invalidateCurrentSession()
  }

  /// Sends one command within the current session. A failed command drops
  /// the session, so the next command reconnects instead of reusing a
  /// session WebDriverAgent may no longer have. Answers about the screen,
  /// such as a missing alert, come from a working session and keep it.
  private func command(
    _ method: String,
    _ pathComponents: [String],
    body: [String: Any]? = nil
  ) async throws -> Any? {
    let identifier = try await connectedSessionIdentifier()
    guard let agent else {
      throw AutomationError.commandFailed("no WebDriverAgent address")
    }
    do {
      return try await request(
        agent,
        method: method,
        pathComponents: ["session", identifier] + pathComponents,
        body: body
      )
    } catch let error as AutomationError where !error.isLinkFailure {
      throw error
    } catch {
      await invalidateCurrentSession()
      throw error
    }
  }

  /// The worker and the battery reading use the session at the same time,
  /// so a command that arrives while the session is being connected waits
  /// for that connection instead of failing as a lost link.
  private func connectedSessionIdentifier() async throws -> String {
    if let sessionIdentifier {
      return sessionIdentifier
    }
    if let connection {
      return try await connection.value
    }
    let connection = Task { try await connect() }
    self.connection = connection
    defer { self.connection = nil }
    return try await connection.value
  }

  /// Reconnects at most once per interval. WebDriverAgent is started only
  /// when the iPhone is reachable and WebDriverAgent does not answer. While
  /// the iPhone is out of reach, such as during a Wi-Fi drop, a start would
  /// only fail, and a run still alive when the iPhone is back is used again.
  private func connect() async throws -> String {
    if let lastConnectionAttempt,
      ContinuousClock.now - lastConnectionAttempt < reconnectInterval
    {
      throw AutomationError.commandFailed("waiting to reconnect to the iPhone")
    }
    lastConnectionAttempt = .now

    guard let address = await host.deviceAddress() else {
      throw AutomationError.commandFailed("the iPhone is out of reach of the Mac")
    }
    let agent = Self.agentURL(address: address, port: configuration.port)
    if await answers(agent) {
      unansweredStarts = 0
      return try await createSession(at: agent)
    }
    if await host.isStartingAgent() {
      throw AutomationError.commandFailed("waiting for WebDriverAgent to start on the iPhone")
    }
    guard unansweredStarts < Self.startAttempts else {
      unansweredStarts = 0
      throw AutomationError.agentDidNotStart(await host.agentOutput())
    }
    unansweredStarts += 1
    try await host.startAgent()
    throw AutomationError.commandFailed("starting WebDriverAgent on the iPhone")
  }

  private func answers(_ agent: URL) async -> Bool {
    let status = try? await request(
      agent,
      method: "GET",
      pathComponents: ["status"],
      body: nil,
      timeout: 3
    )
    return status is [String: Any]
  }

  /// A session without its settings would read the wrong app, so it is only
  /// used once they are in place.
  private func createSession(at agent: URL) async throws -> String {
    let value = try await request(
      agent,
      method: "POST",
      pathComponents: ["session"],
      body: ["capabilities": ["alwaysMatch": [String: Any]()]]
    )
    guard
      let session = value as? [String: Any],
      let identifier = session["sessionId"] as? String,
      !identifier.isEmpty
    else {
      throw AutomationError.malformedResponse("sessionId is missing")
    }
    do {
      try await configure(identifier, at: agent)
    } catch {
      _ = try? await request(
        agent, method: "DELETE", pathComponents: ["session", identifier], body: nil)
      throw error
    }
    self.agent = agent
    sessionIdentifier = identifier
    return identifier
  }

  private func configure(_ identifier: String, at agent: URL) async throws {
    let window = try await request(
      agent,
      method: "GET",
      pathComponents: ["session", identifier, "window", "rect"],
      body: nil
    )
    guard
      let window = window as? [String: Any],
      let width = (window["width"] as? NSNumber)?.doubleValue,
      let height = (window["height"] as? NSNumber)?.doubleValue
    else {
      throw AutomationError.malformedResponse("window rect is incomplete")
    }

    // Capture apps keep their main thread busy, so waiting for idle would
    // delay every tap by the full timeout. Readiness is judged from the screen.
    // WebDriverAgent reads the app under the detection point as the one in
    // front, so system screens such as Control Center count as in front
    // instead of leaving the app under them looking tappable. Its default
    // point, near the top left corner, is where notification banners appear,
    // so the center of the screen is used instead.
    _ = try await request(
      agent,
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

  private func invalidateCurrentSession() async {
    guard let sessionIdentifier, let agent else { return }
    self.sessionIdentifier = nil
    _ = try? await request(
      agent,
      method: "DELETE",
      pathComponents: ["session", sessionIdentifier],
      body: nil
    )
  }

  private static func agentURL(address: String, port: Int) -> URL {
    let host = address.contains(":") ? "[\(address)]" : address
    return URL(string: "http://\(host):\(port)")!
  }

  private func request(
    _ agent: URL,
    method: String,
    pathComponents: [String],
    body: [String: Any]?,
    timeout: TimeInterval = 30
  ) async throws -> Any? {
    let url = pathComponents.reduce(agent) { partialURL, component in
      partialURL.appendingPathComponent(component)
    }
    var request = URLRequest(url: url, timeoutInterval: timeout)
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
      throw AutomationError.commandFailed(String(describing: error))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AutomationError.malformedResponse("response is not HTTP")
    }
    guard !data.isEmpty else {
      if (200..<300).contains(httpResponse.statusCode) {
        return nil
      }
      throw AutomationError.commandFailed("HTTP \(httpResponse.statusCode)")
    }

    guard
      let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      throw AutomationError.malformedResponse("response body is not a JSON object")
    }
    let value = payload["value"]

    if let errorValue = value as? [String: Any],
      let errorName = errorValue["error"] as? String
    {
      let message = errorValue["message"] as? String ?? errorName
      switch errorName {
      case "no such alert":
        throw AutomationError.noSuchAlert
      case "stale element reference":
        throw AutomationError.staleElement
      // WebDriverAgent answers with these when its session is gone or when
      // XCTest fails inside it, which a new session usually gets past.
      case "invalid session id", "session not created", "unknown error", "timeout":
        throw AutomationError.commandFailed(message)
      default:
        throw AutomationError.refused("\(errorName): \(message)")
      }
    }
    if !(200..<300).contains(httpResponse.statusCode) {
      throw AutomationError.commandFailed("HTTP \(httpResponse.statusCode)")
    }
    return value
  }
}
