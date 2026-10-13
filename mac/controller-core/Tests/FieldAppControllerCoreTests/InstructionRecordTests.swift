import XCTest

@testable import FieldAppControllerCore

final class InstructionRecordTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("field-app-test-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testARecordingLoopIsCarriedOverToTheNextStart() throws {
    try InstructionRecord(deviceID: "device", directory: directory).save(.running)

    let carriedOver = InstructionRecord(deviceID: "device", directory: directory).carriedOver()

    XCTAssertEqual(carriedOver, .running)
  }

  /// After a pause the device is left alone, so a start has nothing to take up.
  func testAPauseIsNotCarriedOver() throws {
    let record = InstructionRecord(deviceID: "device", directory: directory)
    try record.save(.running)
    try record.save(.paused)

    XCTAssertNil(record.carriedOver())
  }

  func testNothingIsCarriedOverForADeviceWithoutARecord() throws {
    try InstructionRecord(deviceID: "other", directory: directory).save(.running)

    XCTAssertNil(InstructionRecord(deviceID: "device", directory: directory).carriedOver())
  }

  func testDeviceNameCannotLeaveTheDirectory() throws {
    let record = InstructionRecord(deviceID: "../outside", directory: directory)
    try record.save(.running)

    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(record.carriedOver(), .running)
  }
}
