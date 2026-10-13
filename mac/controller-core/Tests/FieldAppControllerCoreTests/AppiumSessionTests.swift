import Foundation
import XCTest

@testable import FieldAppControllerCore

/// Stands in for the Appium server: answers each request with the reply set
/// for its method and path, and records what was asked.
private final class AppiumStub: URLProtocol, @unchecked Sendable {
  static let host = "appium.test"
  private static let lock = NSLock()
  nonisolated(unsafe) private static var replies: [String: (status: Int, body: String)] = [:]
  nonisolated(unsafe) private static var received: [(request: String, body: Data)] = []

  static func answer(_ replies: [String: (status: Int, body: String)]) {
    lock.withLock {
      self.replies = replies
      received = []
    }
  }

  static var requests: [String] {
    lock.withLock { received.map(\.request) }
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
      Self.received.append((key, body))
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

final class AppiumSessionTests: XCTestCase {
  private static let newSession = (200, #"{"value":{"sessionId":"s1","capabilities":{}}}"#)
  private static let window = (200, #"{"value":{"x":0,"y":0,"width":375,"height":812}}"#)
  private static let done = (200, #"{"value":null}"#)

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(AppiumStub.self)
  }

  override func tearDown() {
    URLProtocol.unregisterClass(AppiumStub.self)
    super.tearDown()
  }

  private func configuration() throws -> AppiumDeviceConfiguration {
    try AppiumDeviceConfiguration(
      serverURL: URL(string: "http://\(AppiumStub.host)")!,
      deviceID: "device",
      developmentTeam: "TEAM",
      bundleIdentifier: "com.bakerdata.minute",
      wdaLocalPort: 8100
    )
  }

  /// A session that named the app would read it even under Control Center,
  /// and its buttons would look tappable there.
  func testSessionReadsTheAppAtTheCenterOfTheScreen() async throws {
    AppiumStub.answer([
      "POST /session": Self.newSession,
      "GET /session/s1/window/rect": Self.window,
      "POST /session/s1/appium/settings": Self.done,
    ])

    _ = try await AppiumSession.start(configuration: configuration())

    let capabilities =
      (AppiumStub.body(of: "POST /session")?["capabilities"] as? [String: Any])?["alwaysMatch"]
      as? [String: Any]
    let settings = AppiumStub.body(of: "POST /session/s1/appium/settings")?["settings"]
      as? [String: Any]
    XCTAssertNotNil(capabilities)
    XCTAssertNil(capabilities?["appium:bundleId"])
    XCTAssertEqual(settings?["activeAppDetectionPoint"] as? String, "187,406")
  }

  func testElementThatLeftTheScreenKeepsTheSession() async throws {
    AppiumStub.answer([
      "POST /session": Self.newSession,
      "GET /session/s1/window/rect": Self.window,
      "POST /session/s1/appium/settings": Self.done,
      "POST /session/s1/element/e1/click": (
        404,
        #"{"value":{"error":"stale element reference","message":"The previously found element is not present in the current view anymore"}}"#
      ),
      "GET /session/s1/alert/text": (
        404, #"{"value":{"error":"no such alert","message":"An attempt was made to operate on a modal dialog when one was not open"}}"#
      ),
    ])
    let session = try await AppiumSession.start(configuration: configuration())

    do {
      try await session.tap(
        AutomationElement(identifier: "e1", name: "record-stop", type: "XCUIElementTypeButton")
      )
      XCTFail("A tap on an element that left the screen did not fail.")
    } catch {
      XCTAssertEqual(error as? AppiumAutomationError, .staleElement)
    }
    let alert = try await session.systemAlertText()

    XCTAssertNil(alert)
    XCTAssertEqual(AppiumStub.requests.filter { $0 == "POST /session" }.count, 1)
    XCTAssertFalse(AppiumStub.requests.contains("DELETE /session/s1"))
  }

  /// A refusal is an answer about the screen, which a person has to look at.
  /// Treated as a lost link, it would reconnect and refuse again forever.
  func testRefusalKeepsTheSessionAndAnUnreachableAgentDropsIt() async throws {
    AppiumStub.answer([
      "POST /session": Self.newSession,
      "GET /session/s1/window/rect": Self.window,
      "POST /session/s1/appium/settings": Self.done,
      "POST /session/s1/execute/sync": (
        400,
        #"{"value":{"error":"invalid element state","message":"Failed to find button with label '閉じる'"}}"#
      ),
      "POST /session/s1/element/e1/click": (
        500,
        #"{"value":{"error":"unknown error","message":"Could not proxy command to the remote server"}}"#
      ),
      "DELETE /session/s1": Self.done,
    ])
    let session = try await AppiumSession.start(configuration: configuration())

    do {
      try await session.tapSystemAlertButton("閉じる")
      XCTFail("A refused button press did not fail.")
    } catch let error as AppiumAutomationError {
      XCTAssertEqual(error, .refused("invalid element state: Failed to find button with label '閉じる'"))
      XCTAssertFalse(error.isLinkFailure)
    }
    let pressed = AppiumStub.body(of: "POST /session/s1/execute/sync")
    XCTAssertEqual(pressed?["script"] as? String, "mobile: alert")
    XCTAssertEqual(
      (pressed?["args"] as? [[String: String]])?.first,
      ["action": "accept", "buttonLabel": "閉じる"]
    )
    XCTAssertFalse(AppiumStub.requests.contains("DELETE /session/s1"))

    do {
      try await session.tap(
        AutomationElement(identifier: "e1", name: "record-stop", type: "XCUIElementTypeButton")
      )
      XCTFail("A tap through an unreachable WebDriverAgent did not fail.")
    } catch let error as AppiumAutomationError {
      XCTAssertTrue(error.isLinkFailure)
    }
    XCTAssertEqual(AppiumStub.requests.last, "DELETE /session/s1")
  }

  func testSessionWhoseSettingsFailIsNotUsed() async throws {
    AppiumStub.answer([
      "POST /session": Self.newSession,
      "GET /session/s1/window/rect": Self.window,
      "POST /session/s1/appium/settings": (
        500, #"{"value":{"error":"unknown error","message":"settings were not applied"}}"#
      ),
      "DELETE /session/s1": Self.done,
    ])

    do {
      _ = try await AppiumSession.start(configuration: configuration())
      XCTFail("A session without its settings was used.")
    } catch {
      XCTAssertEqual(error as? AppiumAutomationError, .commandFailed("settings were not applied"))
    }
    XCTAssertEqual(AppiumStub.requests.last, "DELETE /session/s1")
  }
}
