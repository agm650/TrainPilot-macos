import XCTest
@testable import TrainPilot

final class SemanticVersionTests: XCTestCase {
    func testOrdering() {
        XCTAssertLessThan(
            SemanticVersion("1.2.0")!,
            SemanticVersion("1.3.0")!
        )
        XCTAssertLessThan(
            SemanticVersion("1.9.9")!,
            SemanticVersion("2.0.0")!
        )
        XCTAssertEqual(
            SemanticVersion("1.2.0")!,
            SemanticVersion("1.2.0")!
        )
    }
}
