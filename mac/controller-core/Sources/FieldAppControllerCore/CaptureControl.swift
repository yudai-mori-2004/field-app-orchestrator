import Foundation

public enum DesiredCaptureState: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
  case running
  case paused
}

/// What the device shows, as far as the operation definition can tell.
public enum CaptureObservation: Sendable, Equatable {
  case state(String)
  case outsideApp(String?)
  case unknown(String)
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

public enum CaptureStep: Sendable, Equatable {
  case settled
  case waitForApp
  case perform(CaptureAction)
}

/// A step that was planned from a screen the app has already left, such as a
/// button that disappeared before the tap. The worker observes again.
public protocol CaptureStaleStepError: Error {}

/// A step whose button something the definition does not describe covers,
/// such as a sheet the app opened over it. While the screen stays as it was,
/// the worker handles it as an unknown screen.
public protocol CaptureCoveredStepError: Error {}

/// An error from the link to the device rather than from the app. The worker
/// keeps observing after one, because the link may come back.
public protocol CaptureLinkError: Error {
  var isLinkFailure: Bool { get }
}

public protocol CaptureAppAdapter: Sendable {
  /// Reads the screen. `previous` is the last observation, so a screen that
  /// has not moved can be confirmed with a single read.
  func observe(after previous: CaptureObservation?) async throws -> CaptureObservation
  func nextStep(
    toward desiredState: DesiredCaptureState,
    from observation: CaptureObservation
  ) async throws -> CaptureStep
  func perform(_ action: CaptureAction, from observation: CaptureObservation) async throws
  /// A way back to known ground from an unknown screen, such as restarting
  /// the app. Nil when only a person can help.
  func recovery(from observation: CaptureObservation) async throws -> CaptureAction?
}

extension CaptureAppAdapter {
  public func recovery(from observation: CaptureObservation) async throws -> CaptureAction? {
    nil
  }
}

public enum DeviceWorkerPhase: Sendable, Equatable {
  case idle
  case stable
  case waitingForApp
  case transitioning(CaptureAction)
  case reconnecting(String)
  case needsAttention(String)
  case stopped
}

public struct DeviceWorkerSnapshot: Sendable, Equatable {
  /// Nil until the first command, while the worker only observes.
  public let desiredState: DesiredCaptureState?
  public let observation: CaptureObservation?
  public let phase: DeviceWorkerPhase
  public let revision: UInt64

  public init(
    desiredState: DesiredCaptureState?,
    observation: CaptureObservation?,
    phase: DeviceWorkerPhase,
    revision: UInt64
  ) {
    self.desiredState = desiredState
    self.observation = observation
    self.phase = phase
    self.revision = revision
  }
}

public enum DeviceWorkerEvent: Sendable, Equatable {
  case observed(CaptureObservation)
  case performing(CaptureAction)
  case phaseChanged(DeviceWorkerPhase)
}

public actor DeviceWorker {
  public let deviceID: String

  private let adapter: any CaptureAppAdapter
  private let onEvent: (@Sendable (DeviceWorkerEvent) -> Void)?
  private var desiredState: DesiredCaptureState?
  private var observation: CaptureObservation? {
    didSet {
      if let observation, observation != oldValue {
        onEvent?(.observed(observation))
      }
    }
  }
  private var phase: DeviceWorkerPhase = .idle {
    didSet {
      if phase != oldValue {
        onEvent?(.phaseChanged(phase))
      }
    }
  }
  private var revision: UInt64 = 0
  private var isReconciling = false
  private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []
  private var isStopping = false
  private var shouldStop = false
  /// Set once the paused state is reached. From then on the worker leaves
  /// the device alone, so a person can use it during a break, until the next
  /// command arrives.
  private var leavesDeviceAlone = false

  public init(
    deviceID: String,
    adapter: any CaptureAppAdapter,
    onEvent: (@Sendable (DeviceWorkerEvent) -> Void)? = nil
  ) {
    self.deviceID = deviceID
    self.adapter = adapter
    self.onEvent = onEvent
  }

  /// A new command also means a person has looked at the device, so it ends
  /// a wait for attention the same way `acknowledgeAndRetry` does. The next
  /// step is still planned from a fresh observation.
  public func setDesiredState(_ newState: DesiredCaptureState) {
    guard !isStopping, !shouldStop else { return }
    desiredState = newState
    leavesDeviceAlone = false
    if case .needsAttention = phase {
      phase = .idle
    }
    revision &+= 1
  }

  /// Leaves the device paused before the worker stops. An action already sent
  /// is allowed to finish, because a tap cannot be taken back. A worker that
  /// needs attention is stopped without tapping.
  public func pauseAndStop(maxTransitions: Int = 12) async -> DeviceWorkerSnapshot {
    guard !isStopping, !shouldStop else { return snapshot() }
    isStopping = true
    desiredState = .paused
    leavesDeviceAlone = false
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
    leavesDeviceAlone = false
    revision &+= 1
  }

  public func snapshot() -> DeviceWorkerSnapshot {
    DeviceWorkerSnapshot(
      desiredState: desiredState,
      observation: observation,
      phase: phase,
      revision: revision
    )
  }

  /// How long a caller should wait before the next reconcile. A settled
  /// device only needs to be checked for the app's own moves, such as a
  /// recording reaching its limit, so it is read rarely to spare the
  /// device's radio and battery. Commands should not wait for this delay.
  public func nextObservationDelay() -> Duration {
    switch phase {
    case .waitingForApp:
      return .seconds(1)
    case .reconnecting:
      return .seconds(2)
    case .transitioning:
      return .milliseconds(500)
    case .idle, .stable, .needsAttention, .stopped:
      return .seconds(10)
    }
  }

  @discardableResult
  public func reconcileUntilStable(maxTransitions: Int = 12) async -> DeviceWorkerSnapshot {
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
    // One recovery per pass: a screen that is still unknown afterwards needs
    // a person.
    var mayRecover = true
    var coveredStep: (observation: CaptureObservation, detail: String)?
    while observationsTowardTarget < maxTransitions {
      guard !shouldStop else {
        phase = .stopped
        return snapshot()
      }

      do {
        var current = try await adapter.observe(after: observation)
        // The state still matches under whatever covers its button, so the
        // screen as a whole is one the definition does not describe.
        if let coveredStep, coveredStep.observation == current {
          current = .unknown(coveredStep.detail)
        }
        coveredStep = nil
        observation = current
        // Starting the worker must not change what the device is doing; a
        // recording in progress continues until someone asks for a state.
        guard let requested = desiredState else {
          phase = .idle
          return snapshot()
        }
        if leavesDeviceAlone {
          return snapshot()
        }
        if case .unknown(let detail) = current {
          if mayRecover, let recovery = try await adapter.recovery(from: current) {
            mayRecover = false
            observationsTowardTarget += 1
            phase = .transitioning(recovery)
            onEvent?(.performing(recovery))
            try await adapter.perform(recovery, from: current)
            continue
          }
          phase = .needsAttention(detail)
          return snapshot()
        }

        if requested != target {
          target = requested
          observationsTowardTarget = 0
        }
        observationsTowardTarget += 1

        switch try await adapter.nextStep(toward: requested, from: current) {
        case .settled:
          phase = .stable
          leavesDeviceAlone = requested == .paused
          return snapshot()
        case .waitForApp:
          phase = .waitingForApp
          return snapshot()
        case .perform(let action):
          phase = .transitioning(action)
          onEvent?(.performing(action))
          do {
            try await adapter.perform(action, from: current)
          } catch let error as CaptureCoveredStepError {
            coveredStep = (current, Self.describe(error))
          }
        }
      } catch is CaptureStaleStepError {
        continue
      } catch {
        let description = Self.describe(error)
        // A lost link says nothing about the app, and a tap whose answer was
        // lost may or may not have landed. Either way the next step is
        // planned from a fresh observation once the link is back.
        if let linkError = error as? CaptureLinkError, linkError.isLinkFailure {
          if case .reconnecting = phase {
            return snapshot()
          }
          phase = .reconnecting(description)
        } else {
          phase = .needsAttention(description)
        }
        return snapshot()
      }
    }

    phase = .needsAttention(
      "The app did not reach the requested state within the transition limit.")
    return snapshot()
  }

  private static func describe(_ error: any Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  }
}
