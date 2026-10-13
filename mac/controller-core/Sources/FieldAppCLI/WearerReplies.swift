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
        return "録画を始めました。"
      case .paused:
        return "録画を止めました。"
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
        return "iPhoneがMacにつながっていません。つながったら録画を始めます。"
      case .paused:
        return "iPhoneがMacにつながっていません。つながったら止めます。録画中なら、それまで録画は続きます。"
      }
    case .stopped:
      return "Macのプログラムが終了しています。担当者に連絡してください。"
    case .idle, .waitingForApp, .transitioning:
      return underWay(toward: goal)
    }
  }

  private func underWay(toward goal: DesiredCaptureState) -> String {
    switch goal {
    case .running:
      return "録画の準備をしています。このまま待ってください。"
    case .paused:
      return "止めているところです。このまま待ってください。"
    }
  }
}
