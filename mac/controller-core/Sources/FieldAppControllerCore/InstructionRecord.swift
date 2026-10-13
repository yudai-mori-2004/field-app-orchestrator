import Foundation

/// Keeps a device's last command on disk. A worker that starts after its
/// process died reads it, so that a recording loop that was under way goes
/// on without the wearer tapping again.
public struct InstructionRecord: Sendable {
  private let file: URL

  public init(deviceID: String, directory: URL) {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let name = deviceID.addingPercentEncoding(withAllowedCharacters: allowed) ?? deviceID
    file = directory.appendingPathComponent("\(name).instruction")
  }

  /// `~/Library/Application Support/field-app`
  public static var defaultDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("field-app", isDirectory: true)
  }

  /// The command to take up at the start. Only a recording loop is taken
  /// up. After a pause the worker leaves the device alone until the next
  /// command, the same as when nothing was recorded.
  public func carriedOver() -> DesiredCaptureState? {
    guard
      let text = try? String(contentsOf: file, encoding: .utf8),
      DesiredCaptureState(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
        == .running
    else {
      return nil
    }
    return .running
  }

  public func save(_ state: DesiredCaptureState) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("\(state.rawValue)\n".utf8).write(to: file, options: .atomic)
  }
}
