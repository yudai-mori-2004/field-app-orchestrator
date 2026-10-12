import SwiftUI

struct MockTaskRootView: View {
  @ObservedObject var session: MockCaptureSession

  var body: some View {
    ZStack {
      Color(red: 0.04, green: 0.06, blue: 0.11)
        .ignoresSafeArea()

      switch session.screen {
      case .home:
        home
      case .taskDetail:
        taskDetail
      case .recording:
        recording
      }
    }
    .preferredColorScheme(.dark)
  }

  private var home: some View {
    VStack(alignment: .leading, spacing: 20) {
      safeBanner

      Text("Mock Tasks")
        .font(.largeTitle.bold())

      TextField("Search tasks", text: $session.searchText)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("home-search-input")

      if session.searchText.isEmpty || "mock task".localizedCaseInsensitiveContains(session.searchText) {
        Button(action: session.showTaskDetail) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Mock Task")
              .font(.title3.bold())
            Text("Exercises the controller without recording or submitting data.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("featured-card-mock-task")
      }

      Spacer()

      Text("Completed mock sessions: \(session.completedRecordings)")
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("mock-completed-count")
    }
    .padding()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home-screen")
  }

  private var taskDetail: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        Button("Close", systemImage: "xmark", action: session.closeTaskDetail)
          .accessibilityIdentifier("record-close")
        Spacer()
      }

      safeBanner

      Spacer()

      Text("Mock Task")
        .font(.largeTitle.bold())

      Text(durationDescription)
        .font(.title3.monospacedDigit())
        .accessibilityIdentifier("tutorial-duration-hint")

      Text("Starting this task only runs an in-memory countdown. The app has no camera, file-writing, or network implementation.")
        .foregroundStyle(.secondary)

      Button("Start task", action: session.startRecording)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("record-start-task")

      Spacer()
    }
    .padding()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("record-screen")
  }

  private var recording: some View {
    VStack(spacing: 24) {
      safeBanner

      Spacer()

      Image(systemName: "timer")
        .font(.system(size: 64))
        .foregroundStyle(.cyan)

      Text("Mock recording")
        .font(.largeTitle.bold())

      Text(formattedRemainingTime)
        .font(.system(size: 48, weight: .semibold, design: .monospaced))
        .accessibilityIdentifier("recording-time-remaining")

      Text("The controller should observe this screen until the countdown ends. The app then returns to home automatically.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)

      Button("Stop mock session", action: session.stopRecording)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("record-stop-task")

      Spacer()
    }
    .padding()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("recording-screen")
  }

  private var safeBanner: some View {
    Label("MOCK — NO RECORDING OR UPLOAD", systemImage: "checkmark.shield.fill")
      .font(.caption.bold())
      .foregroundStyle(.green)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.green.opacity(0.12), in: Capsule())
      .accessibilityIdentifier("mock-safety-banner")
  }

  private var durationDescription: String {
    session.recordingDurationSeconds == 30 * 60
      ? "Duration: 30 minutes"
      : "Test duration: \(session.recordingDurationSeconds) seconds"
  }

  private var formattedRemainingTime: String {
    let minutes = session.remainingSeconds / 60
    let seconds = session.remainingSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
