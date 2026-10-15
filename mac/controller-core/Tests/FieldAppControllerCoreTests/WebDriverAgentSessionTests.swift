import Foundation
import XCTest

@testable import FieldAppControllerCore

/// Stands in for WebDriverAgent: answers each request with the reply set for
/// its method and path, and records what was asked.
private final class AgentStub: URLProtocol, @unchecked Sendable {
  static let host = "agent.test"
  private static let lock = NSLock()
  nonisolated(unsafe) private static var replies: [String: (status: Int, body: String)] = [:]
  nonisolated(unsafe) private static var received: [(request: String, port: Int?, body: Data)] = []

  static func answer(_ replies: [String: (status: Int, body: String)]) {
    lock.withLock {
      self.replies = replies
      received = []
    }
  }

  static var requests: [String] {
    lock.withLock { received.map(\.request) }
  }

  static var ports: Set<Int?> {
    lock.withLock { Set(received.map(\.port)) }
  }

  static func body(of request: String) -> [String: Any]? {
    let data = lock.withLock { received.first { $0.request == request }?.body }
    return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
    let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
    let reply = Self.lock.withLock {
      Self.received.append((key, request.url?.port, body))
      return Self.replies[key]
    }
    let (status, text) =
      reply ?? (404, #"{"value":{"error":"unknown command","message":"no reply set"}}"#)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["content-type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(text.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func read(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

/// Stands in for Xcode: reports the iPhone's address and records starts.
private actor StubHost: WebDriverAgentHost {
  private(set) var address: String? = AgentStub.host
  private(set) var starting = false
  private(set) var starts = 0

  func deviceAddress() -> String? { address }
  func startAgent() { starts += 1 }
  func isStartingAgent() -> Bool { starting }
  func agentOutput() -> String { "The signing certificate has expired." }

  func moveOutOfReach() { address = nil }
  func setStarting(_ starting: Bool) { self.starting = starting }
}

final class WebDriverAgentSessionTests: XCTestCase {
  private static let agentUp = (200, #"{"value":{"ready":true}}"#)
  private static let newSession = (200, #"{"value":{"sessionId":"s1","capabilities":{}}}"#)
  private static let window = (200, #"{"value":{"x":0,"y":0,"width":375,"height":812}}"#)
  private static let done = (200, #"{"value":null}"#)
  private static let connected: [String: (status: Int, body: String)] = [
    "GET /status": agentUp,
    "POST /session": newSession,
    "GET /session/s1/window/rect": window,
    "POST /session/s1/appium/settings": done,
  ]

  private var testRunFile: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    URLProtocol.registerClass(AgentStub.self)
    testRunFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("field-app-test-\(UUID().uuidString).xctestrun")
    let testRun: [String: Any] = [
      "WebDriverAgentRunner": ["EnvironmentVariables": ["USE_PORT": "8300"]]
    ]
    try PropertyListSerialization.data(fromPropertyList: testRun, format: .xml, options: 0)
      .write(to: testRunFile)
  }

  override func tearDownWithError() throws {
    URLProtocol.unregisterClass(AgentStub.self)
    try? FileManager.default.removeItem(at: testRunFile)
    try super.tearDownWithError()
  }

  private func session(
    host: StubHost,
    reconnectInterval: Duration = .zero
  ) throws -> WebDriverAgentSession {
    let configuration = try WebDriverAgentConfiguration(
      deviceID: "device",
      bundleIdentifier: "com.bakerdata.minute",
      xctestrun: testRunFile
    )
    return WebDriverAgentSession(
      configuration: configuration,
      host: host,
      reconnectInterval: reconnectInterval
    )
  }

  /// A session that named the app would read it even under Control Center,
  /// where its buttons would look tappable.
  func testSessionNamesNoAppAndReadsTheCenterOfTheScreen() async throws {
    AgentStub.answer(Self.connected.merging(["GET /session/s1/wda/locked": (200, #"{"value":false}"#)]) { $1 })
    let session = try session(host: StubHost())

    let locked = try await session.isLocked()

    let capabilities = (AgentStub.body(of: "POST /session")?["capabilities"] as? [String: Any])
    let settings = AgentStub.body(of: "POST /session/s1/appium/settings")?["settings"] as? [String: Any]
    XCTAssertFalse(locked)
    XCTAssertEqual((capabilities?["alwaysMatch"] as? [String: Any])?.isEmpty, true)
    XCTAssertEqual(settings?["activeAppDetectionPoint"] as? String, "187,406")
    XCTAssertEqual(AgentStub.ports, [8300])
  }

  func testElementThatLeftTheScreenKeepsTheSession() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "POST /session/s1/element/e1/click": (
          404,
          #"{"value":{"error":"stale element reference","message":"The previously found element is not present in the current view anymore"}}"#
        ),
        "GET /session/s1/alert/text": (
          404, #"{"value":{"error":"no such alert","message":"An attempt was made to operate on a modal dialog when one was not open"}}"#
        ),
      ]) { $1 })
    let session = try session(host: StubHost())

    do {
      try await session.tap(
        AutomationElement(identifier: "e1", name: "record-stop", type: "XCUIElementTypeButton")
      )
      XCTFail("A tap on an element that left the screen did not fail.")
    } catch {
      XCTAssertEqual(error as? AutomationError, .staleElement)
    }
    let alert = try await session.systemAlertText()

    XCTAssertNil(alert)
    XCTAssertEqual(AgentStub.requests.filter { $0 == "POST /session" }.count, 1)
    XCTAssertFalse(AgentStub.requests.contains("DELETE /session/s1"))
  }

  /// A refusal is an answer about the screen, which a person has to look at.
  /// Treated as a lost link, it would reconnect and refuse again forever.
  func testRefusalKeepsTheSessionAndALostLinkDropsIt() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "POST /session/s1/alert/accept": (
          400,
          #"{"value":{"error":"invalid element state","message":"Failed to find button with label '閉じる'"}}"#
        ),
        "POST /session/s1/element/e1/click": (
          500, #"{"value":{"error":"invalid session id","message":"Session does not exist"}}"#
        ),
        "DELETE /session/s1": Self.done,
      ]) { $1 })
    let session = try session(host: StubHost())

    do {
      try await session.tapSystemAlertButton("閉じる")
      XCTFail("A refused button press did not fail.")
    } catch let error as AutomationError {
      XCTAssertEqual(error, .refused("invalid element state: Failed to find button with label '閉じる'"))
      XCTAssertFalse(error.isLinkFailure)
    }
    XCTAssertEqual(AgentStub.body(of: "POST /session/s1/alert/accept")?["name"] as? String, "閉じる")
    XCTAssertFalse(AgentStub.requests.contains("DELETE /session/s1"))

    do {
      try await session.tap(
        AutomationElement(identifier: "e1", name: "record-stop", type: "XCUIElementTypeButton")
      )
      XCTFail("A tap in a lost session did not fail.")
    } catch let error as AutomationError {
      XCTAssertTrue(error.isLinkFailure)
    }
    XCTAssertEqual(AgentStub.requests.last, "DELETE /session/s1")
  }

  func testSessionWhoseSettingsFailIsNotUsed() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "POST /session/s1/appium/settings": (
          500, #"{"value":{"error":"unknown error","message":"settings were not applied"}}"#
        ),
        "DELETE /session/s1": Self.done,
      ]) { $1 })
    let session = try session(host: StubHost())

    do {
      _ = try await session.isLocked()
      XCTFail("A session without its settings was used.")
    } catch {
      XCTAssertEqual(error as? AutomationError, .commandFailed("settings were not applied"))
    }
    XCTAssertEqual(AgentStub.requests.last, "DELETE /session/s1")
  }

  /// The worker's first read and the battery reading start together. Failing
  /// the one that arrives during the connection would show a lost link at
  /// every start.
  func testCommandsThatArriveTogetherShareOneConnection() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "GET /session/s1/wda/locked": (200, #"{"value":false}"#),
        "GET /session/s1/wda/batteryInfo": (200, #"{"value":{"level":0.5,"state":1}}"#),
      ]) { $1 })
    let session = try session(host: StubHost(), reconnectInterval: .seconds(10))

    async let locked = session.isLocked()
    async let battery = session.batteryState()
    let (isLocked, batteryState) = try await (locked, battery)

    XCTAssertFalse(isLocked)
    XCTAssertEqual(batteryState.level, 0.5)
    XCTAssertEqual(AgentStub.requests.filter { $0 == "POST /session" }.count, 1)
  }

  /// Read as it arrives, 10% is a little above 0.1, and a pause set for 10%
  /// waits for the next level the iPhone reports, which was 5% on a device.
  func testBatteryLevelIsReadInWholePercent() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "GET /session/s1/wda/batteryInfo": (
          200, #"{"value":{"level":0.10000000149011612,"state":1}}"#
        )
      ]) { $1 })
    let session = try session(host: StubHost())

    let battery = try await session.batteryState()

    var pauseAtTenPercent = BatteryGuard(threshold: 0.10)
    XCTAssertEqual(battery.level, 0.10)
    XCTAssertTrue(pauseAtTenPercent.shouldPause(for: battery))
  }

  /// A start during a Wi-Fi drop would only fail, and would end a run that
  /// may still be alive.
  func testIPhoneOutOfReachIsWaitedForWithoutStartingWebDriverAgent() async throws {
    AgentStub.answer([:])
    let host = StubHost()
    await host.moveOutOfReach()
    let session = try session(host: host)

    do {
      _ = try await session.isLocked()
      XCTFail("A command reached an iPhone out of reach.")
    } catch let error as AutomationError {
      XCTAssertTrue(error.isLinkFailure)
    }

    let starts = await host.starts
    XCTAssertEqual(starts, 0)
    XCTAssertEqual(AgentStub.requests, [])
  }

  func testSilentWebDriverAgentIsStartedOnceAndGivenTimeToComeUp() async throws {
    AgentStub.answer([:])
    let host = StubHost()
    let session = try session(host: host)

    _ = try? await session.isLocked()
    await host.setStarting(true)
    _ = try? await session.isLocked()

    let starts = await host.starts
    XCTAssertEqual(starts, 1)
  }

  private static let automationStopped = (
    500,
    #"{"value":{"error":"invalid argument","message":"Error Domain=XCTDaemonErrorDomain Code=41 \"Not authorized for performing UI testing actions.\""}}"#
  )

  /// After both volume buttons are held on the iPhone, WebDriverAgent still
  /// answers its status. Reconnecting to that run would be refused forever.
  func testAutomationStoppedOnTheIPhoneStartsWebDriverAgentAgain() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "POST /session/s1/wda/apps/activate": Self.automationStopped,
        "DELETE /session/s1": Self.done,
      ]) { $1 })
    let host = StubHost()
    let session = try session(host: host)

    do {
      try await session.activateApp()
      XCTFail("An action after the automation was stopped did not fail.")
    } catch let error as AutomationError {
      XCTAssertTrue(error.isLinkFailure)
    }
    _ = try? await session.activateApp()

    let starts = await host.starts
    XCTAssertEqual(starts, 1)
    XCTAssertEqual(AgentStub.requests.filter { $0 == "POST /session" }.count, 1)
  }

  /// With UI automation turned off in the developer settings, every start
  /// is stopped again, and a person has to turn it back on.
  func testAutomationThatStaysStoppedIsHandedToAPerson() async throws {
    AgentStub.answer(
      Self.connected.merging([
        "POST /session/s1/wda/apps/activate": Self.automationStopped,
        "DELETE /session/s1": Self.done,
      ]) { $1 })
    let host = StubHost()
    let session = try session(host: host)

    var lastError: Error?
    for _ in 0..<8 {
      do {
        try await session.activateApp()
      } catch {
        lastError = error
      }
    }

    let starts = await host.starts
    XCTAssertEqual(starts, 3)
    XCTAssertEqual((lastError as? AutomationError)?.isLinkFailure, false)
  }

  func testWebDriverAgentThatNeverAnswersIsHandedToAPerson() async throws {
    AgentStub.answer([:])
    let host = StubHost()
    let session = try session(host: host)

    var lastError: Error?
    for _ in 0..<4 {
      do {
        _ = try await session.isLocked()
      } catch {
        lastError = error
      }
    }

    let starts = await host.starts
    XCTAssertEqual(starts, 3)
    XCTAssertEqual(
      lastError as? AutomationError,
      .agentDidNotStart("The signing certificate has expired.")
    )
    XCTAssertEqual((lastError as? AutomationError)?.isLinkFailure, false)
  }
}
