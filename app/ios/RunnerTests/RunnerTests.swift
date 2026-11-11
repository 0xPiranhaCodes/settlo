import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testSeenCapKeepsNumericallyNewestActivityIDs() {
    let retained = ReminderChannel.recentSeen(Set((1...1001).map { "manual:\($0)" }))
    XCTAssertEqual(retained.count, 500)
    XCTAssertEqual(retained.first, "manual:502")
    XCTAssertEqual(retained.last, "manual:1001")
    XCTAssertFalse(retained.contains("manual:9"))
    XCTAssertTrue(retained.contains("manual:1000"))
  }

  func testSeenCapPreservesLargeBigintIDs() {
    XCTAssertEqual(ReminderChannel.recentSeen(["manual:9", "manual:10", "manual:9223372036854775806"]),
                   ["manual:9", "manual:10", "manual:9223372036854775806"])
  }

}
