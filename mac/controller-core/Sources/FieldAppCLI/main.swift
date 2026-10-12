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
      return "Usage: field-app {--course|--validate-course} <path-to-course-json>"
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
    let coursePath = operation.path
    let course = try loadCourse(from: coursePath)
    try course.validate()

    if operation.isValidationOnly {
      print("Valid course: \(course.displayName) [\(course.identifier)]")
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
      bundleIdentifier: course.bundleIdentifier,
      wdaLocalPort: wdaLocalPort
    )

    print("Connecting \(course.displayName) to \(deviceLabel)...")
    let session = try await AppiumSession.start(configuration: deviceConfiguration)
    let adapter = try CaptureCourseAdapter(session: session, course: course)
    let worker = DeviceWorker(deviceID: deviceLabel, adapter: adapter)
    let pollingTask = Task {
      while !Task.isCancelled {
        _ = await worker.reconcileUntilStable()
        try? await Task.sleep(nanoseconds: 500_000_000)
      }
    }

    print("Worker is paused. Commands: start, pause, status, retry, quit")
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
        try await shutDown(worker: worker, pollingTask: pollingTask, session: session)
        return
      case "":
        continue
      default:
        print("Unknown command. Use: start, pause, status, retry, quit")
      }
    }

    try await shutDown(worker: worker, pollingTask: pollingTask, session: session)
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

  private static func parseOperation(_ arguments: [String]) throws -> CourseOperation {
    guard arguments.count == 3 else {
      throw FieldAppCLIError.usage
    }
    switch arguments[1] {
    case "--course":
      return CourseOperation(path: arguments[2], isValidationOnly: false)
    case "--validate-course":
      return CourseOperation(path: arguments[2], isValidationOnly: true)
    default:
      throw FieldAppCLIError.usage
    }
  }

  private static func loadCourse(from path: String) throws -> CaptureCourseDefinition {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(CaptureCourseDefinition.self, from: data)
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

  private static func snapshotDescription(_ snapshot: DeviceWorkerSnapshot) -> String {
    "desired=\(snapshot.desiredState.rawValue) phase=\(String(describing: snapshot.phase)) "
      + "screen=\(String(describing: snapshot.observedScreen)) revision=\(snapshot.revision)"
  }
}

private struct CourseOperation {
  let path: String
  let isValidationOnly: Bool
}
