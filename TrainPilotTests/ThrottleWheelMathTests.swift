import XCTest
import Testing
@testable import TrainPilot

struct ThrottleWheelRotationTests {
    private let size = CGSize(width: 200, height: 200)

    private func point(_ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: 100 + cos(radians) * 80, y: 100 + sin(radians) * 80)
    }

    private func rotate(_ value: Double, from start: Double, to end: Double) -> Double {
        ThrottleWheelMath.percentage(
            from: point(start), to: point(end), in: size, startingAt: value
        )
    }

    @Test func counterclockwiseRotationCannotLeaveZero() {
        var value = 0.0
        for angle in stride(from: 140.0, through: -220.0, by: -10.0) {
            value = rotate(value, from: angle, to: angle - 10)
            #expect(value == 0)
        }
        #expect(abs(rotate(value, from: 130, to: 156) - 10) < 0.001)
    }

    @Test func clockwiseRotationCannotWrapPastMaximum() {
        var value = 100.0
        for angle in stride(from: 400.0, through: 760.0, by: 10.0) {
            value = rotate(value, from: angle, to: angle + 10)
            #expect(value == 100)
        }
        #expect(abs(rotate(value, from: 50, to: 24) - 90) < 0.001)
    }

    @Test func fullSweepWorksInBothDirections() {
        var value = 0.0
        for angle in stride(from: 140.0, to: 400.0, by: 10.0) {
            value = rotate(value, from: angle, to: angle + 10)
        }
        #expect(abs(value - 100) < 0.001)
        for angle in stride(from: 400.0, to: 140.0, by: -10.0) {
            value = rotate(value, from: angle, to: angle - 10)
        }
        #expect(abs(value) < 0.001)
    }

    @Test func stationaryClickDoesNotChangeSpeed() {
        #expect(rotate(0, from: 40, to: 40) == 0)
        #expect(rotate(50, from: 140, to: 140) == 50)
    }

    @Test func smallMovementsAccumulate() {
        var value = 0.0
        for step in 0..<26 {
            value = rotate(value, from: 140 + Double(step) / 10, to: 140 + Double(step + 1) / 10)
        }
        #expect(abs(value - 1) < 0.001)
    }

    @Test func centerSamplesAreIgnored() {
        let center = CGPoint(x: 100, y: 100)
        #expect(ThrottleWheelMath.percentage(
            from: center, to: point(40), in: size, startingAt: 25
        ) == 25)
        #expect(ThrottleWheelMath.percentage(
            from: point(140), to: center, in: size, startingAt: 25
        ) == 25)
    }
}

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
