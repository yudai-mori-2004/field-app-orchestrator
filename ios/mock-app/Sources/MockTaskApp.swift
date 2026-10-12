import SwiftUI

@main
struct MockTaskApp: App {
  @StateObject private var session = MockCaptureSession()

  var body: some Scene {
    WindowGroup {
      MockTaskRootView(session: session)
    }
  }
}
