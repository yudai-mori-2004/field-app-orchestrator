import Foundation

public enum DesiredCaptureState: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
  case running
  case paused
}

/// What the device shows, as far as the operation definition can tell.
public enum CaptureObservation: Sendable, Equatable {
  /// A screen of the app that the definition describes.
  case state(String)
  /// A system alert in front of everything, with its text.
  case systemAlert(String)
  case locked
  /// Another app, the home screen, or a system screen such as Control
  /// Center is in front.
  case outsideApp(String?)
  /// A screen of the app that the definition does not describe.
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

/// What to do next. Every observation leads to one of these.
public enum CaptureStep: Sendable, Equatable {
  /// The device is in the requested state.
  case settled
  /// The app moves on by itself, such as a countdown ending.
  case waitForApp
  case perform(CaptureAction)
  /// Leaves a screen the definition does not describe, such as by restarting
  /// the app. The worker allows one per pass; `reason` says what a person
  /// should look at when it is not allowed.
  case recover(CaptureAction, reason: String)
  /// Only a person can go on from here.
  case needsAttention(String)
}

/// A step that was planned from a screen the app has already left, such as a
/// button that disappeared before or during its tap. The worker observes
/// again.
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
  /// The command the worker follows changed, whichever source it came from.
  case desiredStateChanged(DesiredCaptureState)
}

public actor DeviceWorker {
  public let deviceID: String

  private let adapter: any CaptureAppAdapter
  private let onEvent: (@Sendable (DeviceWorkerEvent) -> Void)?
  private var desiredState: DesiredCaptureState? {
    didSet {
      if let desiredState, desiredState != oldValue {
        onEvent?(.desiredStateChanged(desiredState))
      }
    }
  }
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
  /// The latest command revision the current phase answers. The phase can be
  /// older than a command until a reconcile pass has looked at the device
  /// for it. `passRevision` is the revision a pass last planned from.
  private var answeredRevision: UInt64 = 0
  private var passRevision: UInt64 = 0
  private var isReconciling = false
  private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []
  private var outcomeWaiters:
    [UInt64: (revision: UInt64, continuation: CheckedContinuation<DeviceWorkerSnapshot?, Never>)] =
      [:]
  private var nextOutcomeWaiter: UInt64 = 0
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
  /// step is still planned from a fresh observation. Returns the command's
  /// revision, for `outcome(of:within:)`.
  @discardableResult
  public func setDesiredState(_ newState: DesiredCaptureState) -> UInt64 {
    guard !isStopping, !shouldStop else { return revision }
    desiredState = newState
    leavesDeviceAlone = false
    if case .needsAttention = phase {
      phase = .idle
    }
    revision &+= 1
    return revision
  }

  /// Waits until the device has answered the command at `revision`: a pass
  /// that planned from it reached the requested state, needs a person, or
  /// lost the link. Nil when `timeout` passes first, such as while the app
  /// counts down or the device is slow to answer; the phase at that moment
  /// may still be the one from before the command.
  public func outcome(
    of revision: UInt64,
    within timeout: Duration
  ) async -> DeviceWorkerSnapshot? {
    if hasAnswered(revision) {
      return snapshot()
    }
    nextOutcomeWaiter &+= 1
    let waiter = nextOutcomeWaiter
    return await withCheckedContinuation { continuation in
      outcomeWaiters[waiter] = (revision, continuation)
      Task {
        try? await Task.sleep(for: timeout)
        expireOutcomeWaiter(waiter)
      }
    }
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
    resumeAnsweredOutcomeWaiters()
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
      switch phase {
      case .needsAttention, .reconnecting:
        // No command is acted on until these clear, so they answer every
        // command given so far, including one that arrived during the pass.
        answeredRevision = revision
      case .idle, .stable, .waitingForApp, .transitioning, .stopped:
        answeredRevision = passRevision
      }
      resumeAnsweredOutcomeWaiters()
      let waiters = reconciliationWaiters
      reconciliationWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
    return await reconcile(maxTransitions: maxTransitions)
  }

  private func hasAnswered(_ revision: UInt64) -> Bool {
    switch phase {
    case .stopped:
      return true
    case .stable, .needsAttention, .reconnecting:
      return answeredRevision >= revision
    case .idle, .waitingForApp, .transitioning:
      return false
    }
  }

  private func resumeAnsweredOutcomeWaiters() {
    for (waiter, entry) in outcomeWaiters where hasAnswered(entry.revision) {
      outcomeWaiters[waiter] = nil
      entry.continuation.resume(returning: snapshot())
    }
  }

  private func expireOutcomeWaiter(_ waiter: UInt64) {
    outcomeWaiters.removeValue(forKey: waiter)?.continuation.resume(returning: nil)
  }

  /// The transition limit applies to each requested state, so a pause that
  /// arrives late in a restart still gets the full limit to settle.
  private func reconcile(maxTransitions: Int) async -> DeviceWorkerSnapshot {
    var target = desiredState
    var observationsTowardTarget = 0
    // One recovery per pass: a screen that is still unknown afterwards needs
    // a person.
    var mayRecover = true
    var coveredStep: CoveredStep?
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
        passRevision = revision
        // Starting the worker must not change what the device is doing; a
        // recording in progress continues until someone asks for a state.
        guard let requested = desiredState else {
          phase = .idle
          return snapshot()
        }
        if leavesDeviceAlone {
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
        case .needsAttention(let reason):
          phase = .needsAttention(reason)
          return snapshot()
        case .recover(let action, let reason):
          guard mayRecover else {
            phase = .needsAttention(reason)
            return snapshot()
          }
          mayRecover = false
          coveredStep = try await run(action, from: current)
        case .perform(let action):
          coveredStep = try await run(action, from: current)
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

  /// Performs one action. When something the definition does not describe
  /// covers its button, returns the screen the action was planned from.
  private func run(
    _ action: CaptureAction,
    from observation: CaptureObservation
  ) async throws -> CoveredStep? {
    phase = .transitioning(action)
    onEvent?(.performing(action))
    do {
      try await adapter.perform(action, from: observation)
      return nil
    } catch let error as CaptureCoveredStepError {
      return CoveredStep(observation: observation, detail: Self.describe(error))
    }
  }

  private struct CoveredStep {
    let observation: CaptureObservation
    let detail: String
  }

  private static func describe(_ error: any Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  }
}
