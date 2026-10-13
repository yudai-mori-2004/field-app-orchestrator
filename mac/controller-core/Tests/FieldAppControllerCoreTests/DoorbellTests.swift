import XCTest

@testable import FieldAppControllerCore

final class DoorbellTests: XCTestCase {
  func testRingEndsAWaitEarly() async {
    let doorbell = Doorbell()
    let began = ContinuousClock.now
    async let waited: Void = doorbell.wait(for: .seconds(30))
    try? await Task.sleep(for: .milliseconds(50))
    await doorbell.ring()
    await waited

    XCTAssertLessThan(ContinuousClock.now - began, .seconds(5))
  }

  func testRingBeforeAWaitIsNotLost() async {
    let doorbell = Doorbell()
    await doorbell.ring()
    let began = ContinuousClock.now

    await doorbell.wait(for: .seconds(30))

    XCTAssertLessThan(ContinuousClock.now - began, .seconds(5))
  }

  func testWaitEndsAfterTheDelayWithoutARing() async {
    let doorbell = Doorbell()
    let began = ContinuousClock.now

    await doorbell.wait(for: .milliseconds(100))

    XCTAssertGreaterThanOrEqual(ContinuousClock.now - began, .milliseconds(100))
  }
}
