import Foundation

public struct BatteryState: Sendable, Equatable {
  public let level: Double
  public let isCharging: Bool

  public init(level: Double, isCharging: Bool) {
    self.level = level
    self.isCharging = isCharging
  }
}

/// Decides when a draining battery should pause capture: once each time the
/// level falls to the threshold while the device is not charging. A wearer
/// who starts again below the threshold is not stopped a second time.
public struct BatteryGuard: Sendable {
  public let threshold: Double
  private var wasAboveThreshold = true

  public init(threshold: Double) {
    self.threshold = threshold
  }

  public mutating func shouldPause(for battery: BatteryState) -> Bool {
    let isLow = battery.level <= threshold && !battery.isCharging
    defer { wasAboveThreshold = !isLow }
    return isLow && wasAboveThreshold
  }
}
