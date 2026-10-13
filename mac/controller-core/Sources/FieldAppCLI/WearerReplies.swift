import FieldAppControllerCore

/// The sentences the wearer's Shortcut reads aloud after a start or a pause.
/// The wearer cannot see the Mac or the screen, so each sentence says what
/// happened and, when the device is stuck, the one thing a person can do.
actor WearerReplies {
  /// Replies in a row that found the device waiting for a person. A second
  /// one means closing what was on the screen did not help.
  private var unresolvedAttention = 0

  /// `outcome` is nil when the device had not answered in time. A sentence
  /// follows the state the device was sent toward, which a later command
  /// may have changed from `requested`.
  func sentence(requested: DesiredCaptureState, outcome: DeviceWorkerSnapshot?) -> String {
    guard let outcome else {
      return underWay(toward: requested)
    }
    let goal = outcome.desiredState ?? requested
    switch outcome.phase {
    case .stable:
      unresolvedAttention = 0
      switch goal {
      case .running:
        return "撮影を開始しました。"
      case .paused:
        return "撮影を終了しました。"
      }
    case .needsAttention:
      unresolvedAttention += 1
      guard unresolvedAttention == 1 else {
        return "直りませんでした。担当者に連絡してください。"
      }
      // The next tap is the person's acknowledgment, and the worker plans
      // again from what the screen shows then.
      return "iPhoneの画面に出ている表示を閉じてから、もう一度同じようにたたいてください。"
    case .reconnecting:
      switch goal {
      case .running:
        return "iPhoneがMacにつながっていません。つながったら撮影を開始します。"
      case .paused:
        return "iPhoneがMacにつながっていません。つながったら撮影を終了します。撮影中なら、それまで撮影は続きます。"
      }
    case .stopped:
      return "Macのプログラムが終了しています。担当者に連絡してください。"
    case .idle, .waitingForApp, .transitioning:
      return underWay(toward: goal)
    }
  }

  /// Asks for another tap later. This reply cannot carry the result, and
  /// the next tap is answered with what the device shows by then.
  private func underWay(toward goal: DesiredCaptureState) -> String {
    switch goal {
    case .running:
      return "撮影の準備に時間がかかっています。少ししてから、もう一度たたいてください。"
    case .paused:
      return "撮影の終了に時間がかかっています。少ししてから、もう一度たたいてください。"
    }
  }
}
