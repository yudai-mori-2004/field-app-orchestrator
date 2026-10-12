import Foundation

public enum DesiredCaptureState: String, Sendable, Equatable {
  case running
  case paused
}

public enum CaptureBlockReason: Sendable, Equatable {
  case unknownScreen(String)
  case loginRequired
  case permissionPrompt
  case warning(String)
}

public enum CaptureScreen: Sendable, Equatable {
  case home
  case taskReady
  case recording
  case blocked(CaptureBlockReason)
}

public enum CaptureAction: String, Sendable, Equatable {
  case openTask
  case closeTask
  case startRecording
  case stopRecording
}

public protocol CaptureAppAdapter: Sendable {
  func observe() async throws -> CaptureScreen
  func perform(_ action: CaptureAction) async throws
}

public enum DeviceWorkerPhase: Sendable, Equatable {
  case idle
  case stable
  case transitioning(CaptureAction)
  case needsAttention(String)
  case stopped
}

public struct DeviceWorkerSnapshot: Sendable, Equatable {
  public let desiredState: DesiredCaptureState
  public let observedScreen: CaptureScreen?
  public let phase: DeviceWorkerPhase
  public let revision: UInt64

  public init(
    desiredState: DesiredCaptureState,
    observedScreen: CaptureScreen?,
    phase: DeviceWorkerPhase,
    revision: UInt64
  ) {
    self.desiredState = desiredState
    self.observedScreen = observedScreen
    self.phase = phase
    self.revision = revision
  }
}

public actor DeviceWorker {
  public let deviceID: String

  private let adapter: any CaptureAppAdapter
  private var desiredState: DesiredCaptureState = .paused
  private var observedScreen: CaptureScreen?
  private var phase: DeviceWorkerPhase = .idle
  private var revision: UInt64 = 0
  private var isReconciling = false
  private var shouldStop = false

  public init(deviceID: String, adapter: any CaptureAppAdapter) {
    self.deviceID = deviceID
    self.adapter = adapter
  }

  public func setDesiredState(_ newState: DesiredCaptureState) {
    guard !shouldStop else { return }
    desiredState = newState
    revision &+= 1
  }

  public func stopWorker() {
    shouldStop = true
    revision &+= 1
    phase = .stopped
  }

  public func acknowledgeAndRetry() {
    guard case .needsAttention = phase, !shouldStop else { return }
    phase = .idle
    revision &+= 1
  }

  public func snapshot() -> DeviceWorkerSnapshot {
    DeviceWorkerSnapshot(
      desiredState: desiredState,
      observedScreen: observedScreen,
      phase: phase,
      revision: revision
    )
  }

  @discardableResult
  public func reconcileUntilStable(maxTransitions: Int = 4) async -> DeviceWorkerSnapshot {
    guard !isReconciling else { return snapshot() }
    guard !shouldStop else { return snapshot() }
    if case .needsAttention = phase {
      return snapshot()
    }

    isReconciling = true
    defer { isReconciling = false }
    return await reconcile(maxTransitions: maxTransitions)
  }

  public func run(pollIntervalMilliseconds: UInt64 = 500) async {
    guard !isReconciling, !shouldStop else { return }

    while !Task.isCancelled, !shouldStop {
      _ = await reconcileUntilStable()

      if case .needsAttention = phase {
        return
      }

      do {
        try await Task.sleep(nanoseconds: pollIntervalMilliseconds * 1_000_000)
      } catch {
        return
      }
    }
  }

  private func reconcile(maxTransitions: Int) async -> DeviceWorkerSnapshot {
    for _ in 0..<maxTransitions {
      guard !shouldStop else {
        phase = .stopped
        return snapshot()
      }

      do {
        let screen = try await adapter.observe()
        observedScreen = screen

        switch screen {
        case .blocked(let reason):
          phase = .needsAttention(Self.describe(reason))
          return snapshot()
        case .home, .taskReady, .recording:
          break
        }

        guard let action = Self.nextAction(desiredState: desiredState, screen: screen) else {
          phase = .stable
          return snapshot()
        }

        phase = .transitioning(action)
        try await adapter.perform(action)
      } catch {
        phase = .needsAttention(String(describing: error))
        return snapshot()
      }
    }

    phase = .needsAttention("The app did not reach the requested state within the transition limit.")
    return snapshot()
  }

  public static func nextAction(
    desiredState: DesiredCaptureState,
    screen: CaptureScreen
  ) -> CaptureAction? {
    switch (desiredState, screen) {
    case (.running, .home):
      return .openTask
    case (.running, .taskReady):
      return .startRecording
    case (.running, .recording):
      return nil
    case (.paused, .home):
      return nil
    case (.paused, .taskReady):
      return .closeTask
    case (.paused, .recording):
      return .stopRecording
    case (_, .blocked):
      return nil
    }
  }

  private static func describe(_ reason: CaptureBlockReason) -> String {
    switch reason {
    case .unknownScreen(let detail):
      return "Unknown screen: \(detail)"
    case .loginRequired:
      return "Login is required."
    case .permissionPrompt:
      return "A permission prompt requires operator review."
    case .warning(let detail):
      return "Warning requires operator review: \(detail)"
    }
  }
}
