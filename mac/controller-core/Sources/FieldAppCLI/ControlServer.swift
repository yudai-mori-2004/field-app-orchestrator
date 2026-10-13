import Foundation
import Network

enum ControlRequest: String, Sendable {
  case start
  case pause
}

/// Accepts start and pause requests over HTTP from the Shortcuts that the
/// wearer runs with back taps. The reply is a short sentence for the Shortcut
/// to read aloud, because the wearer cannot see the screen.
final class ControlServer: Sendable {
  private let listener: NWListener
  private let token: String
  private let handle: @Sendable (ControlRequest) async -> String?
  private let queue = DispatchQueue(label: "field-app.control")

  init(
    port: UInt16,
    token: String,
    handle: @escaping @Sendable (ControlRequest) async -> String?
  ) throws {
    guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
      throw ControlServerError.invalidPort(port)
    }
    listener = try NWListener(using: .tcp, on: endpointPort)
    self.token = token
    self.handle = handle
  }

  func start() {
    listener.newConnectionHandler = { [self] connection in
      connection.start(queue: queue)
      receive(on: connection)
    }
    listener.start(queue: queue)
  }

  func stop() {
    listener.cancel()
  }

  private func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
      [self] data, _, _, error in
      guard error == nil, let data, let text = String(data: data, encoding: .utf8) else {
        connection.cancel()
        return
      }
      let (status, request) = parse(text)
      guard let request else {
        respond(on: connection, status: status, body: "")
        return
      }
      Task {
        // No sentence means the command was not taken, so the Shortcut is
        // given nothing to read aloud.
        guard let reply = await handle(request) else {
          respond(on: connection, status: "503 Service Unavailable", body: "")
          return
        }
        respond(on: connection, status: "200 OK", body: reply)
      }
    }
  }

  /// Reads the request line, for example `POST /start?token=... HTTP/1.1`.
  private func parse(_ text: String) -> (status: String, request: ControlRequest?) {
    let requestLine = text.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
    guard requestLine.count >= 2, requestLine[0] == "POST",
      let components = URLComponents(string: String(requestLine[1]))
    else {
      return ("405 Method Not Allowed", nil)
    }
    let suppliedToken = components.queryItems?.first { $0.name == "token" }?.value
    guard suppliedToken == token else {
      return ("401 Unauthorized", nil)
    }
    guard let request = ControlRequest(rawValue: String(components.path.dropFirst())) else {
      return ("404 Not Found", nil)
    }
    return ("200 OK", request)
  }

  private func respond(on connection: NWConnection, status: String, body: String) {
    let bytes = Data(body.utf8)
    let header =
      "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\n"
      + "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
    connection.send(
      content: Data(header.utf8) + bytes,
      completion: .contentProcessed { _ in connection.cancel() }
    )
  }
}

enum ControlServerError: Error, LocalizedError {
  case invalidPort(UInt16)

  var errorDescription: String? {
    switch self {
    case .invalidPort(let port):
      return "FAO_CONTROL_PORT \(port) is not a usable port."
    }
  }
}
