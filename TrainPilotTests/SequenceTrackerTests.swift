import XCTest
@testable import TrainPilot

final class SequenceTrackerTests: XCTestCase {
    func testOrderedSequence() {
        var tracker = SequenceTracker()
        tracker.reset(to: 10)

        XCTAssertEqual(tracker.evaluate(11), .accept)
        XCTAssertEqual(tracker.evaluate(12), .accept)
        XCTAssertEqual(tracker.lastSequence, 12)
    }

    func testDuplicateIsIgnored() {
        var tracker = SequenceTracker()
        tracker.reset(to: 10)

        XCTAssertEqual(tracker.evaluate(10), .duplicate)
        XCTAssertEqual(tracker.lastSequence, 10)
    }

    func testGapRequestsResynchronization() {
        var tracker = SequenceTracker()
        tracker.reset(to: 10)

        XCTAssertEqual(
            tracker.evaluate(13),
            .gap(expected: 11, received: 13)
        )
        XCTAssertEqual(tracker.lastSequence, 10)
    }
}
