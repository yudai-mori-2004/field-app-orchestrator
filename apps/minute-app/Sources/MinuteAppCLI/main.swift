import FieldAppControllerCore
import Foundation
import MinuteAppAdapter

private enum MinuteCLIError: Error, LocalizedError {
  case usage
  case missingEnvironment(String)
  case invalidEnvironment(String)

  var errorDescription: String? {
    switch self {
    case .usage:
      return "Usage: minute-app --config <path-to-local-json>"
    case .missingEnvironment(let name):
      return "\(name) must be set at runtime."
    case .invalidEnvironment(let detail):
      return detail
    }
  }
}

@main
struct MinuteAppCommand {
  static func main() async throws {
    let configPath = try parseConfigPath(CommandLine.arguments)
    let minuteConfiguration = try loadConfiguration(from: configPath)
    let environment = ProcessInfo.processInfo.environment
    let deviceID = try requiredEnvironment("FAO_DEVICE_ID", from: environment)
    let developmentTeam = try requiredEnvironment(
      "FAO_DEVELOPMENT_TEAM",
      from: environment
    )
    let serverURL = try appiumURL(from: environment)
    let wdaLocalPort = try port(from: environment)
    let deviceConfiguration = try AppiumDeviceConfiguration(
      serverURL: serverURL,
      deviceID: deviceID,
      developmentTeam: developmentTeam,
      bundleIdentifier: MinuteDataAdapter.bundleIdentifier,
      wdaLocalPort: wdaLocalPort
    )

    print("Connecting the Minute worker to the configured iPhone...")
    let session = try await AppiumSession.start(configuration: deviceConfiguration)
    let adapter = MinuteDataAdapter(
      session: session,
      configuration: minuteConfiguration
    )
    let worker = DeviceWorker(deviceID: "configured-device", adapter: adapter)
    let pollingTask = Task {
      while !Task.isCancelled {
        _ = await worker.reconcileUntilStable()
        try? await Task.sleep(nanoseconds: 500_000_000)
      }
    }

    print("Minute worker is paused. Commands: start, pause, status, retry, quit")
    while let command = readLine(strippingNewline: true)?.lowercased() {
      switch command {
      case "start":
        await worker.setDesiredState(.running)
        let snapshot = await worker.reconcileUntilStable()
        print(snapshotDescription(snapshot))
      case "pause":
        await worker.setDesiredState(.paused)
        let snapshot = await worker.reconcileUntilStable()
        print(snapshotDescription(snapshot))
      case "status":
        print(await snapshotDescription(worker.snapshot()))
      case "retry":
        await worker.acknowledgeAndRetry()
        let snapshot = await worker.reconcileUntilStable()
        print(snapshotDescription(snapshot))
      case "quit":
        await shutDown(worker: worker, pollingTask: pollingTask, session: session)
        return
      case "":
        continue
      default:
        print("Unknown command. Use: start, pause, status, retry, quit")
      }
    }

    await shutDown(worker: worker, pollingTask: pollingTask, session: session)
  }

  private static func shutDown(
    worker: DeviceWorker,
    pollingTask: Task<Void, Never>,
    session: AppiumSession
  ) async {
    await worker.setDesiredState(.paused)
    let finalSnapshot = await worker.reconcileUntilStable()
    print("Stopping: \(snapshotDescription(finalSnapshot))")
    await worker.stopWorker()
    pollingTask.cancel()
    _ = await pollingTask.value
    await session.close()
  }

  private static func parseConfigPath(_ arguments: [String]) throws -> String {
    guard arguments.count == 3, arguments[1] == "--config" else {
      throw MinuteCLIError.usage
    }
    return arguments[2]
  }

  private static func loadConfiguration(
    from path: String
  ) throws -> MinuteAppConfiguration {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(MinuteAppConfiguration.self, from: data)
  }

  private static func requiredEnvironment(
    _ name: String,
    from environment: [String: String]
  ) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
      throw MinuteCLIError.missingEnvironment(name)
    }
    return value
  }

  private static func appiumURL(from environment: [String: String]) throws -> URL {
    let rawValue = environment["FAO_APPIUM_URL"] ?? "http://127.0.0.1:4723/"
    guard let url = URL(string: rawValue), url.scheme == "http" || url.scheme == "https" else {
      throw MinuteCLIError.invalidEnvironment("FAO_APPIUM_URL must be an HTTP URL.")
    }
    return url
  }

  private static func port(from environment: [String: String]) throws -> Int {
    let rawValue = environment["FAO_WDA_LOCAL_PORT"] ?? "8100"
    guard let value = Int(rawValue), (1024...64535).contains(value) else {
      throw MinuteCLIError.invalidEnvironment(
        "FAO_WDA_LOCAL_PORT must be between 1024 and 64535."
      )
    }
    return value
  }

  private static func snapshotDescription(_ snapshot: DeviceWorkerSnapshot) -> String {
    "desired=\(snapshot.desiredState.rawValue) phase=\(String(describing: snapshot.phase)) "
      + "screen=\(String(describing: snapshot.observedScreen)) revision=\(snapshot.revision)"
  }
}
