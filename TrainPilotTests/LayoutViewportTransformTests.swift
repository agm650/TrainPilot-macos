import CoreGraphics
import XCTest
@testable import TrainPilot

final class LayoutViewportTransformTests: XCTestCase {
    func testLayoutToCanvasAndInverse() {
        let transform = LayoutViewportTransform(zoom: 2, panX: 30, panY: -10)
        let layoutPoint = LayoutPoint(x: 12, y: 8)

        let canvasPoint = transform.canvasPoint(for: layoutPoint)

        XCTAssertEqual(canvasPoint.x, 54, accuracy: 0.0001)
        XCTAssertEqual(canvasPoint.y, 6, accuracy: 0.0001)
        XCTAssertEqual(transform.layoutPoint(for: canvasPoint), layoutPoint)
    }

    func testSnapHandlesPositiveAndNegativeCoordinates() {
        let transform = LayoutViewportTransform()

        XCTAssertEqual(
            transform.snapped(
                LayoutPoint(x: 103, y: 58),
                gridSpacing: 20,
                enabled: true
            ),
            LayoutPoint(x: 100, y: 60)
        )
        XCTAssertEqual(
            transform.snapped(
                LayoutPoint(x: -31, y: -9),
                gridSpacing: 20,
                enabled: true
            ),
            LayoutPoint(x: -40, y: 0)
        )
    }

    func testDisabledSnapReturnsOriginalPoint() {
        let point = LayoutPoint(x: 103, y: 58)
        XCTAssertEqual(
            LayoutViewportTransform().snapped(
                point,
                gridSpacing: 20,
                enabled: false
            ),
            point
        )
    }

    func testZoomIsClamped() {
        XCTAssertEqual(LayoutViewportTransform(zoom: 0.01).zoom, 0.25)
        XCTAssertEqual(LayoutViewportTransform(zoom: 10).zoom, 4)
    }

    func testPanDoesNotAlterLayoutCoordinates() {
        let original = LayoutPoint(x: 40, y: 60)
        let transform = LayoutViewportTransform(zoom: 1.5)
            .pannedBy(x: 300, y: -200)

        XCTAssertEqual(
            transform.layoutPoint(for: transform.canvasPoint(for: original)),
            original
        )
    }

    func testZoomRoundTripKeepsAnchorStable() {
        let anchor = CGPoint(x: 250, y: 180)
        let original = LayoutViewportTransform(zoom: 1, panX: 40, panY: 30)
        let zoomed = original.zoomed(to: 3, around: anchor)
        let restored = zoomed.zoomed(to: 1, around: anchor)

        XCTAssertEqual(restored.panX, original.panX, accuracy: 0.0001)
        XCTAssertEqual(restored.panY, original.panY, accuracy: 0.0001)
    }
}
