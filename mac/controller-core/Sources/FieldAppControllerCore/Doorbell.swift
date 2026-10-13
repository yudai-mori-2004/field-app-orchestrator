/// Lets a command cut short the wait between observations, so a long wait
/// while the device is settled never delays the response to the wearer.
public actor Doorbell {
  private var waiter: CheckedContinuation<Void, Never>?
  private var generation = 0
  private var rangWhileAway = false

  public init() {}

  public func ring() {
    if let waiter {
      self.waiter = nil
      waiter.resume()
    } else {
      rangWhileAway = true
    }
  }

  public func wait(for delay: Duration) async {
    if rangWhileAway {
      rangWhileAway = false
      return
    }
    generation += 1
    let currentGeneration = generation
    await withCheckedContinuation { continuation in
      waiter = continuation
      Task {
        try? await Task.sleep(for: delay)
        expire(currentGeneration)
      }
    }
  }

  private func expire(_ expiredGeneration: Int) {
    guard expiredGeneration == generation, let waiter else { return }
    self.waiter = nil
    waiter.resume()
  }
}
