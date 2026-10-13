import FieldAppControllerCore

/// The sentence the wearer's Shortcut reads aloud when the Mac has taken a
/// start or a pause. A back tap starts or ends the recording loop, not one
/// recording, so the sentence says the loop is in the Mac's hands and does
/// not wait for the app. The wearer cannot see the Mac or the screen, and
/// hearing it is how they know the tap reached a Mac that is running.
enum WearerReplies {
  static func sentence(for command: DesiredCaptureState) -> String {
    switch command {
    case .running:
      return "撮影を開始します。"
    case .paused:
      return "撮影を終了します。"
    }
  }
}
