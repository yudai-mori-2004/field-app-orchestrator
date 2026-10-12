import FieldAppControllerCore
import Foundation

private enum FieldAppCLIError: Error, LocalizedError {
  case usage
  case missingEnvironment(String)
  case invalidEnvironment(String)
  case notPausedAtExit(String)

  var errorDescription: String? {
    switch self {
    case .usage:
      return "Usage: field-app {--definition|--validate-definition} <path-to-definition-json>"
    case .missingEnvironment(let name):
      return "\(name) must be set at runtime."
    case .invalidEnvironment(let detail):
      return detail
    case .notPausedAtExit(let detail):
      return "Stopped without confirming that the device is paused. Check the device screen. \(detail)"
    }
  }
}

@main
struct FieldAppCommand {
  static func main() async {
    // Keep the event log readable when stdout is a file or a pipe.
    setvbuf(stdout, nil, _IOLBF, 0)
    do {
      try await run()
    } catch {
      let description: String
      if let localizedError = error as? LocalizedError,
        let errorDescription = localizedError.errorDescription
      {
        description = errorDescription
      } else {
        description = String(describing: error)
      }
      FileHandle.standardError.write(Data("field-app: \(description)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func run() async throws {
    let operation = try parseOperation(CommandLine.arguments)
    let definition = try loadDefinition(from: operation.path)
    try definition.validate()

    if operation.isValidationOnly {
      print("Valid definition: \(definition.displayName) [\(definition.identifier)]")
      return
    }

    let environment = ProcessInfo.processInfo.environment
    let deviceID = try requiredEnvironment("FAO_DEVICE_ID", from: environment)
    let developmentTeam = try requiredEnvironment(
      "FAO_DEVELOPMENT_TEAM",
      from: environment
    )
    let serverURL = try appiumURL(from: environment)
    let wdaLocalPort = try port(from: environment)
    let deviceLabel = environment["FAO_DEVICE_LABEL"] ?? "wda-\(wdaLocalPort)"
    let deviceConfiguration = try AppiumDeviceConfiguration(
      serverURL: serverURL,
      deviceID: deviceID,
      developmentTeam: developmentTeam,
      bundleIdentifier: definition.bundleIdentifier,
      wdaLocalPort: wdaLocalPort
    )

    print("Connecting \(definition.displayName) to \(deviceLabel)...")
    let session = try await AppiumSession.start(configuration: deviceConfiguration)
    let adapter = try OperationDefinitionAdapter(session: session, definition: definition)
    let worker = DeviceWorker(deviceID: deviceLabel, adapter: adapter) { event in
      if let line = eventDescription(event) {
        print("\(timestamp()) \(line)")
      }
    }
    let pollingTask = Task {
      while !Task.isCancelled {
        _ = await worker.reconcileUntilStable()
        try? await Task.sleep(nanoseconds: 500_000_000)
      }
    }

    // Typed commands and termination signals share one queue, so Ctrl-C or
    // a closed terminal leaves the device paused the same way `quit` does.
    let (commands, sender) = AsyncStream<String>.makeStream()
    Thread.detachNewThread {
      while let line = readLine(strippingNewline: true) {
        sender.yield(line.lowercased())
      }
      sender.yield("quit")
    }
    var signalSources: [any DispatchSourceSignal] = []
    for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
      source.setEventHandler { sender.yield("quit") }
      source.resume()
      signalSources.append(source)
    }
    defer { signalSources.forEach { $0.cancel() } }

    print("Worker is paused. Commands: start, pause, status, retry, quit")
    for await command in commands {
      switch command {
      case "start":
        await worker.setDesiredState(.running)
        print("\(timestamp()) requested running")
      case "pause":
        await worker.setDesiredState(.paused)
        print("\(timestamp()) requested paused")
      case "status":
        print(await snapshotDescription(worker.snapshot()))
      case "retry":
        await worker.acknowledgeAndRetry()
        print("\(timestamp()) retrying from a fresh observation")
      case "quit":
        try await shutDown(worker: worker, pollingTask: pollingTask, session: session)
        return
      case "":
        continue
      default:
        print("Unknown command. Use: start, pause, status, retry, quit")
      }
    }
  }

  private static func shutDown(
    worker: DeviceWorker,
    pollingTask: Task<Void, Never>,
    session: AppiumSession
  ) async throws {
    // Cancelling polling first would cut off a tap that is already on its way.
    let finalSnapshot = await worker.pauseAndStop()
    pollingTask.cancel()
    _ = await pollingTask.value
    await session.close()

    guard finalSnapshot.phase == .stable else {
      throw FieldAppCLIError.notPausedAtExit(snapshotDescription(finalSnapshot))
    }
    print("Paused and stopped: \(snapshotDescription(finalSnapshot))")
  }

  private static func parseOperation(_ arguments: [String]) throws -> DefinitionOperation {
    guard arguments.count == 3 else {
      throw FieldAppCLIError.usage
    }
    switch arguments[1] {
    case "--definition":
      return DefinitionOperation(path: arguments[2], isValidationOnly: false)
    case "--validate-definition":
      return DefinitionOperation(path: arguments[2], isValidationOnly: true)
    default:
      throw FieldAppCLIError.usage
    }
  }

  private static func loadDefinition(from path: String) throws -> OperationDefinition {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(OperationDefinition.self, from: data)
  }

  private static func requiredEnvironment(
    _ name: String,
    from environment: [String: String]
  ) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
      throw FieldAppCLIError.missingEnvironment(name)
    }
    return value
  }

  private static func appiumURL(from environment: [String: String]) throws -> URL {
    let rawValue = environment["FAO_APPIUM_URL"] ?? "http://127.0.0.1:4723/"
    guard let url = URL(string: rawValue), url.scheme == "http" || url.scheme == "https" else {
      throw FieldAppCLIError.invalidEnvironment("FAO_APPIUM_URL must be an HTTP URL.")
    }
    return url
  }

  private static func port(from environment: [String: String]) throws -> Int {
    let rawValue = environment["FAO_WDA_LOCAL_PORT"] ?? "8100"
    guard let value = Int(rawValue), (1024...64535).contains(value) else {
      throw FieldAppCLIError.invalidEnvironment(
        "FAO_WDA_LOCAL_PORT must be between 1024 and 64535."
      )
    }
    return value
  }

  private static func timestamp() -> String {
    Date.now.formatted(
      .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
    )
  }

  private static func eventDescription(_ event: DeviceWorkerEvent) -> String? {
    switch event {
    case .observed(let observation):
      return "screen \(observationDescription(observation))"
    case .performing(let action):
      return "tap \(action.identifier) (\(action.impact.rawValue))"
    case .phaseChanged(.transitioning):
      return nil
    case .phaseChanged(let phase):
      return "phase \(phaseDescription(phase))"
    }
  }

  private static func snapshotDescription(_ snapshot: DeviceWorkerSnapshot) -> String {
    "desired=\(snapshot.desiredState.rawValue) phase=\(phaseDescription(snapshot.phase)) "
      + "screen=\(snapshot.observation.map(observationDescription) ?? "none") revision=\(snapshot.revision)"
  }

  private static func observationDescription(_ observation: CaptureObservation) -> String {
    switch observation {
    case .state(let state):
      return state
    case .outsideApp(let bundleIdentifier):
      return "outside the app (\(bundleIdentifier ?? "no app in front"))"
    case .unknown(let detail):
      return "unknown (\(detail))"
    }
  }

  private static func phaseDescription(_ phase: DeviceWorkerPhase) -> String {
    switch phase {
    case .idle:
      return "idle"
    case .stable:
      return "stable"
    case .waitingForApp:
      return "waiting for the app"
    case .transitioning(let action):
      return "tapping \(action.identifier)"
    case .needsAttention(let detail):
      return "needs attention: \(detail)"
    case .stopped:
      return "stopped"
    }
  }
}

private struct DefinitionOperation {
  let path: String
  let isValidationOnly: Bool
}
