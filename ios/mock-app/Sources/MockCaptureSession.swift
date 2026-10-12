import Foundation

@MainActor
final class MockCaptureSession: ObservableObject {
  enum Screen {
    case home
    case taskDetail
    case recording
  }

  @Published private(set) var screen: Screen = .home
  @Published private(set) var remainingSeconds: Int
  @Published private(set) var completedRecordings = 0
  @Published var searchText = ""

  let recordingDurationSeconds: Int
  private var countdown: Task<Void, Never>?

  init(defaults: UserDefaults = .standard) {
    let configuredDuration = defaults.integer(forKey: "mockDurationSeconds")
    recordingDurationSeconds = configuredDuration > 0 ? configuredDuration : 30 * 60
    remainingSeconds = recordingDurationSeconds
  }

  func showTaskDetail() {
    guard screen == .home else { return }
    screen = .taskDetail
  }

  func closeTaskDetail() {
    guard screen == .taskDetail else { return }
    screen = .home
  }

  func startRecording() {
    guard screen == .taskDetail else { return }
    countdown?.cancel()
    remainingSeconds = recordingDurationSeconds
    screen = .recording
    countdown = Task { [weak self] in
      guard let self else { return }
      while self.remainingSeconds > 0 {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        self.remainingSeconds -= 1
      }
      self.completedRecordings += 1
      self.screen = .home
    }
  }

  func stopRecording() {
    guard screen == .recording else { return }
    countdown?.cancel()
    countdown = nil
    remainingSeconds = recordingDurationSeconds
    screen = .home
  }
}
