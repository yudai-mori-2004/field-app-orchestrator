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
      print(
        "Valid definition: \(definition.displayName) [\(definition.identifier)]"
          + " (afterRecording: \(definition.afterRecording.rawValue))"
      )
      return
    }

    let environment = ProcessInfo.processInfo.environment
    let deviceID = try requiredEnvironment("FAO_DEVICE_ID", from: environment)
    let deviceLabel = environment["FAO_DEVICE_LABEL"] ?? deviceID
    let batteryStopPercent = try Self.batteryStopPercent(from: environment)
    let agentConfiguration = try WebDriverAgentConfiguration(
      deviceID: deviceID,
      bundleIdentifier: definition.bundleIdentifier,
      xctestrun: agentTestRun(from: environment)
    )

    // Saving submits recordings, so the policy is shown at every start.
    print(
      "Connecting \(definition.displayName) to \(deviceLabel)"
        + " (afterRecording: \(definition.afterRecording.rawValue),"
        + " pause at \(batteryStopPercent)% battery)..."
    )
    // Following the app needs the Mac awake for as long as this runs.
    let awake = ProcessInfo.processInfo.beginActivity(
      options: .idleSystemSleepDisabled,
      reason: "Operating \(definition.displayName) on \(deviceLabel)"
    )
    defer { ProcessInfo.processInfo.endActivity(awake) }

    let session = WebDriverAgentSession(
      configuration: agentConfiguration,
      host: XcodeWebDriverAgentHost(configuration: agentConfiguration)
    )
    let adapter = try OperationDefinitionAdapter(session: session, definition: definition)
    let instructions = InstructionRecord(
      deviceID: deviceID,
      directory: InstructionRecord.defaultDirectory
    )
    let worker = DeviceWorker(deviceID: deviceLabel, adapter: adapter) { event in
      if case .desiredStateChanged(let command) = event {
        do {
          try instructions.save(command)
        } catch {
          FileHandle.standardError.write(
            Data("field-app: could not keep the command for the next start: \(error)\n".utf8)
          )
        }
      }
      if let line = eventDescription(event) {
        // Alert texts carry a title and a message on separate lines.
        print("\(timestamp()) \(line.replacingOccurrences(of: "\n", with: " / "))")
      }
    }
    // A recording loop that was under way when the last process died goes
    // on from here. After a pause or a normal exit, nothing is pressed
    // until the first command.
    let carriesOnRecording = instructions.carriedOver() == .running
    if carriesOnRecording {
      await worker.setDesiredState(.running)
      print("\(timestamp()) requested running (carried over from before this start)")
    }
    let doorbell = Doorbell()
    let pollingTask = Task {
      while !Task.isCancelled {
        _ = await worker.reconcileUntilStable()
        await doorbell.wait(for: worker.nextObservationDelay())
      }
    }
    let batteryTask = Task {
      var batteryGuard = BatteryGuard(threshold: Double(batteryStopPercent) / 100)
      while !Task.isCancelled {
        if let battery = try? await session.batteryState(),
          batteryGuard.shouldPause(for: battery),
          await worker.snapshot().desiredState == .running
        {
          await worker.setDesiredState(.paused)
          await doorbell.ring()
          announce("\(deviceLabel)の電池が残り\(Int(battery.level * 100))%になったので、撮影を止めました。")
        }
        try? await Task.sleep(nanoseconds: 60_000_000_000)
      }
    }
    let controlServer = try startControlServer(
      environment: environment,
      worker: worker,
      doorbell: doorbell
    )
    defer {
      batteryTask.cancel()
      controlServer?.stop()
    }

    // Typed commands and termination signals share one queue, so Ctrl-C or
    // a closed terminal leaves the device paused the same way `quit` does.
    // Without a terminal, as under launchd, nobody types and the end of
    // input says nothing about the operator, so only signals end the run.
    let (commands, sender) = AsyncStream<String>.makeStream()
    let hasTerminal = isatty(STDIN_FILENO) != 0
    if hasTerminal {
      Thread.detachNewThread {
        while let line = readLine(strippingNewline: true) {
          sender.yield(line.lowercased())
        }
        sender.yield("quit")
      }
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

    if !carriesOnRecording {
      print("Observing without tapping until the first command.")
    }
    if hasTerminal {
      print("Commands: start, pause, status, retry, quit")
    }
    for await command in commands {
      switch command {
      case "start":
        await worker.setDesiredState(.running)
        await doorbell.ring()
        print("\(timestamp()) requested running")
      case "pause":
        await worker.setDesiredState(.paused)
        await doorbell.ring()
        print("\(timestamp()) requested paused")
      case "status":
        print(await snapshotDescription(worker.snapshot()))
      case "retry":
        await worker.acknowledgeAndRetry()
        await doorbell.ring()
        print("\(timestamp()) retrying from a fresh observation")
      case "quit":
        try await shutDown(
          worker: worker,
          pollingTask: pollingTask,
          doorbell: doorbell,
          session: session
        )
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
    doorbell: Doorbell,
    session: WebDriverAgentSession
  ) async throws {
    // Cancelling polling first would cut off a tap that is already on its way.
    let finalSnapshot = await worker.pauseAndStop()
    pollingTask.cancel()
    await doorbell.ring()
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

  /// The wearer's back tap reaches the Mac through this server, when
  /// FAO_CONTROL_PORT and FAO_CONTROL_TOKEN are set.
  private static func startControlServer(
    environment: [String: String],
    worker: DeviceWorker,
    doorbell: Doorbell
  ) throws -> ControlServer? {
    guard let rawPort = environment["FAO_CONTROL_PORT"] else { return nil }
    guard let port = UInt16(rawPort) else {
      throw FieldAppCLIError.invalidEnvironment("FAO_CONTROL_PORT must be a port number.")
    }
    let token = try requiredEnvironment("FAO_CONTROL_TOKEN", from: environment)
    guard token.count >= 16 else {
      throw FieldAppCLIError.invalidEnvironment("FAO_CONTROL_TOKEN must be at least 16 characters.")
    }
    let server = try ControlServer(port: port, token: token) { request in
      let requested: DesiredCaptureState = request == .start ? .running : .paused
      // The reply says the Mac has the command and goes on from here. It is
      // sent at once, so the wearer hears right away whether the tap reached
      // the Mac. Held until the recording starts, it would also be read
      // aloud into that recording.
      guard await worker.setDesiredState(requested) else {
        print("\(timestamp()) gave no reply to \(request.rawValue) from the control port (stopping)")
        return nil
      }
      await doorbell.ring()
      let reply = WearerReplies.sentence(for: requested)
      print("\(timestamp()) requested \(requested.rawValue) (\(request.rawValue) from the control port)")
      print("\(timestamp()) replied \"\(reply)\"")
      return reply
    }
    server.start()
    print("Listening for start and pause on port \(port).")
    return server
  }

  /// Prints the message and shows it as a notification on the Mac.
  private static func announce(_ message: String) {
    print("\(timestamp()) \(message)")
    let notifier = Process()
    notifier.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    notifier.arguments = [
      "-e", "on run argv", "-e", "display notification (item 1 of argv) with title \"field-app\"",
      "-e", "end run", message,
    ]
    try? notifier.run()
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

  /// The battery level, in percent, at which a device that is not charging
  /// is paused.
  private static func batteryStopPercent(from environment: [String: String]) throws -> Int {
    let rawValue = environment["FAO_BATTERY_STOP_PERCENT"] ?? "10"
    guard let value = Int(rawValue), (1...50).contains(value) else {
      throw FieldAppCLIError.invalidEnvironment(
        "FAO_BATTERY_STOP_PERCENT must be between 1 and 50."
      )
    }
    return value
  }

  /// The WebDriverAgent build from `tools/setup_wda.sh`, unless
  /// FAO_WDA_XCTESTRUN names another one.
  private static func agentTestRun(from environment: [String: String]) throws -> URL {
    if let path = environment["FAO_WDA_XCTESTRUN"] {
      return URL(fileURLWithPath: path)
    }
    let products = URL(fileURLWithPath: ".wda/Build/Products", isDirectory: true)
    let testRuns =
      (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))?
      .filter { $0.pathExtension == "xctestrun" } ?? []
    guard testRuns.count == 1, let testRun = testRuns.first else {
      throw FieldAppCLIError.invalidEnvironment(
        "Build WebDriverAgent with tools/setup_wda.sh, or set FAO_WDA_XCTESTRUN."
      )
    }
    return testRun
  }

  /// The date is included because a service's log runs over many days.
  private static func timestamp() -> String {
    Date.now.formatted(
      Date.ISO8601FormatStyle(timeZone: .current)
        .year().month().day().dateSeparator(.dash)
        .dateTimeSeparator(.space)
        .time(includingFractionalSeconds: false).timeSeparator(.colon)
    )
  }

  private static func eventDescription(_ event: DeviceWorkerEvent) -> String? {
    switch event {
    case .observed(let observation):
      return "screen \(observationDescription(observation))"
    case .performing(let action):
      return "step \(action.identifier) (\(action.impact.rawValue))"
    case .phaseChanged(.transitioning):
      return nil
    case .phaseChanged(let phase):
      return "phase \(phaseDescription(phase))"
    case .desiredStateChanged:
      // Each source of a command prints its own line.
      return nil
    }
  }

  private static func snapshotDescription(_ snapshot: DeviceWorkerSnapshot) -> String {
    "desired=\(snapshot.desiredState?.rawValue ?? "none") phase=\(phaseDescription(snapshot.phase)) "
      + "screen=\(snapshot.observation.map(observationDescription) ?? "none") revision=\(snapshot.revision)"
  }

  private static func observationDescription(_ observation: CaptureObservation) -> String {
    switch observation {
    case .state(let state):
      return state
    case .systemAlert(let text):
      return "system alert (\(text))"
    case .locked:
      return "locked"
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
      return "running \(action.identifier)"
    case .reconnecting(let detail):
      return "reconnecting: \(detail)"
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
