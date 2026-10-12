import Foundation

public enum DesiredCaptureState: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
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
  case completionPending
  case blocked(CaptureBlockReason)
}

public enum CaptureActionImpact: String, Codable, Sendable, Equatable, Hashable {
  case navigation
  case startsRecording
  case stopsRecording
  case deletesRecording
  case submitsRecording
}

public struct CaptureAction: Sendable, Equatable, Hashable {
  public let identifier: String
  public let impact: CaptureActionImpact

  public init(identifier: String, impact: CaptureActionImpact) {
    self.identifier = identifier
    self.impact = impact
  }
}

public protocol CaptureAppAdapter: Sendable {
  func observe() async throws -> CaptureScreen
  func nextAction(
    desiredState: DesiredCaptureState,
    screen: CaptureScreen
  ) async throws -> CaptureAction?
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
  private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []
  private var isStopping = false
  private var shouldStop = false

  public init(deviceID: String, adapter: any CaptureAppAdapter) {
    self.deviceID = deviceID
    self.adapter = adapter
  }

  public func setDesiredState(_ newState: DesiredCaptureState) {
    guard !isStopping, !shouldStop else { return }
    desiredState = newState
    revision &+= 1
  }

  /// Leaves the device paused before the worker stops. An action already sent
  /// is allowed to finish, because a tap cannot be taken back. A worker that
  /// needs attention is stopped without tapping.
  public func pauseAndStop(maxTransitions: Int = 4) async -> DeviceWorkerSnapshot {
    guard !isStopping, !shouldStop else { return snapshot() }
    isStopping = true
    desiredState = .paused
    revision &+= 1

    while isReconciling {
      await withCheckedContinuation { reconciliationWaiters.append($0) }
    }

    let finalSnapshot: DeviceWorkerSnapshot
    if case .needsAttention = phase {
      finalSnapshot = snapshot()
    } else {
      finalSnapshot = await reconcileExclusively(maxTransitions: maxTransitions)
    }

    shouldStop = true
    phase = .stopped
    revision &+= 1
    return finalSnapshot
  }

  public func acknowledgeAndRetry() {
    guard case .needsAttention = phase, !isStopping, !shouldStop else { return }
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
    guard !isReconciling, !isStopping, !shouldStop else { return snapshot() }
    if case .needsAttention = phase {
      return snapshot()
    }

    return await reconcileExclusively(maxTransitions: maxTransitions)
  }

  private func reconcileExclusively(maxTransitions: Int) async -> DeviceWorkerSnapshot {
    isReconciling = true
    defer {
      isReconciling = false
      let waiters = reconciliationWaiters
      reconciliationWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
    return await reconcile(maxTransitions: maxTransitions)
  }

  /// The transition limit applies to each requested state, so a pause that
  /// arrives late in a restart still gets the full limit to settle.
  private func reconcile(maxTransitions: Int) async -> DeviceWorkerSnapshot {
    var target = desiredState
    var observationsTowardTarget = 0
    while observationsTowardTarget < maxTransitions {
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
        case .home, .taskReady, .recording, .completionPending:
          break
        }

        if desiredState != target {
          target = desiredState
          observationsTowardTarget = 0
        }
        observationsTowardTarget += 1

        guard
          let action = try await adapter.nextAction(
            desiredState: target,
            screen: screen
          )
        else {
          phase = .stable
          return snapshot()
        }

        phase = .transitioning(action)
        try await adapter.perform(action)
      } catch {
        if let localizedError = error as? LocalizedError,
          let description = localizedError.errorDescription
        {
          phase = .needsAttention(description)
        } else {
          phase = .needsAttention(String(describing: error))
        }
        return snapshot()
      }
    }

    phase = .needsAttention(
      "The app did not reach the requested state within the transition limit.")
    return snapshot()
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
