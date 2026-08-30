import XCTest
@testable import TrainPilot

final class ThrottleWheelMathTests: XCTestCase {
    func testAnglesAtExtremes() {
        XCTAssertEqual(
            ThrottleWheelMath.angle(for: 0),
            140,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ThrottleWheelMath.angle(for: 100),
            400,
            accuracy: 0.001
        )
    }

    func testPercentageIsClamped() {
        XCTAssertEqual(
            ThrottleWheelMath.angle(for: -50),
            140,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ThrottleWheelMath.angle(for: 150),
            400,
            accuracy: 0.001
        )
    }
}
