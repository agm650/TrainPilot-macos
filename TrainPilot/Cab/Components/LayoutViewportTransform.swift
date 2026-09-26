import CoreGraphics

struct LayoutViewportTransform: Equatable, Sendable {
    static let minimumZoom = 0.25
    static let maximumZoom = 4.0

    var zoom: Double
    var panX: Double
    var panY: Double

    init(zoom: Double = 1, panX: Double = 0, panY: Double = 0) {
        self.zoom = Self.clampZoom(zoom)
        self.panX = panX
        self.panY = panY
    }

    func canvasPoint(for layoutPoint: LayoutPoint) -> CGPoint {
        CGPoint(
            x: layoutPoint.x * zoom + panX,
            y: layoutPoint.y * zoom + panY
        )
    }

    func layoutPoint(for canvasPoint: CGPoint) -> LayoutPoint {
        LayoutPoint(
            x: (canvasPoint.x - panX) / zoom,
            y: (canvasPoint.y - panY) / zoom
        )
    }

    func pannedBy(x: Double, y: Double) -> LayoutViewportTransform {
        LayoutViewportTransform(
            zoom: zoom,
            panX: panX + x,
            panY: panY + y
        )
    }

    func zoomed(to requestedZoom: Double, around canvasPoint: CGPoint) -> LayoutViewportTransform {
        let anchor = layoutPoint(for: canvasPoint)
        let nextZoom = Self.clampZoom(requestedZoom)
        return LayoutViewportTransform(
            zoom: nextZoom,
            panX: canvasPoint.x - anchor.x * nextZoom,
            panY: canvasPoint.y - anchor.y * nextZoom
        )
    }

    func snapped(
        _ point: LayoutPoint,
        gridSpacing: Double,
        enabled: Bool
    ) -> LayoutPoint {
        guard enabled, gridSpacing.isFinite, gridSpacing > 0 else {
            return point
        }

        return LayoutPoint(
            x: (point.x / gridSpacing).rounded() * gridSpacing,
            y: (point.y / gridSpacing).rounded() * gridSpacing
        )
    }

    static func clampZoom(_ zoom: Double) -> Double {
        min(max(zoom, minimumZoom), maximumZoom)
    }
}
