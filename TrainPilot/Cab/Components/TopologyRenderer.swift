import SwiftUI

enum LayoutInteractionMode: Equatable {
    case editor(showHandles: Bool)
    case operationalReadOnly
}

struct TopologyRuntimeState: Equatable, Sendable {
    enum OccupancyEmphasis: Equatable {
        case none
        case unknown
        case occupied
    }

    enum TurnoutVisualState: Equatable {
        case unknown
        case confirmed
        case transitioning
        case inconsistent
        case failed
    }

    var blockOccupancy: [String: BlockOccupancyState]
    var turnoutStates: [String: Turnout]

    static let empty = TopologyRuntimeState(
        blockOccupancy: [:],
        turnoutStates: [:]
    )

    init(blocks: [Block] = [], turnouts: [Turnout] = []) {
        blockOccupancy = Dictionary(
            uniqueKeysWithValues: blocks.map { ($0.id, $0.occupancyState) }
        )
        turnoutStates = Dictionary(
            uniqueKeysWithValues: turnouts.map { ($0.id, $0) }
        )
    }

    init(
        blockOccupancy: [String: BlockOccupancyState],
        turnoutStates: [String: Turnout]
    ) {
        self.blockOccupancy = blockOccupancy
        self.turnoutStates = turnoutStates
    }

    func occupancyEmphasis(for blockIDs: [String]) -> OccupancyEmphasis {
        let states = blockIDs.compactMap { blockOccupancy[$0] }
        if states.contains(.occupied) { return .occupied }
        if states.contains(.unknown) { return .unknown }
        return .none
    }

    func turnoutVisualState(for id: String) -> TurnoutVisualState {
        guard let turnout = turnoutStates[id] else { return .unknown }
        if turnout.reportedStatus == .invalid ||
            turnout.commandStatus == .failed ||
            turnout.commandStatus == .timeout {
            return .failed
        }
        if turnout.pending || turnout.commandStatus == .pending {
            return .transitioning
        }
        if turnout.reportedStatus == .unknown {
            return .unknown
        }
        if turnout.desiredPosition != turnout.reportedPosition {
            return .inconsistent
        }
        return .confirmed
    }
}

struct TopologyRenderPlan: Equatable, Sendable {
    struct Track: Equatable, Sendable, Identifiable {
        let id: String
        let start: LayoutPoint
        let segments: [LayoutTrackSegment]
        let blockStyles: [LayoutBlockStyle]
        let blockIDs: [String]
    }

    struct Turnout: Equatable, Sendable, Identifiable {
        let presentation: LayoutTurnoutPresentation
        let ports: [LayoutPoint]
        let blockStyles: [LayoutBlockStyle]
        let blockIDs: [String]

        var id: String { presentation.turnoutId }
    }

    let tracks: [Track]
    let turnouts: [Turnout]
    let nodes: [LayoutNodePosition]

    init(
        topology: TopologyDefinition,
        presentation: LayoutPresentationDefinition
    ) {
        let nodePositions = Dictionary(
            uniqueKeysWithValues: presentation.nodes.map { ($0.nodeId, $0) }
        )
        let paths = Dictionary(
            uniqueKeysWithValues: presentation.trackSections.map {
                ($0.trackSectionId, $0)
            }
        )
        let blockStyles = Dictionary(
            uniqueKeysWithValues: presentation.blocks.map { ($0.blockId, $0) }
        )

        tracks = topology.trackSections.compactMap { section -> Track? in
            guard let node = nodePositions[section.nodeAId],
                  let path = paths[section.id] else {
                return nil
            }

            let styles = topology.blocks.compactMap {
                block -> LayoutBlockStyle? in
                guard block.trackSectionIds.contains(section.id) else {
                    return nil
                }
                return blockStyles[block.id]
            }
            let blockIDs = topology.blocks
                .filter { $0.trackSectionIds.contains(section.id) }
                .map(\.id)

            return Track(
                id: section.id,
                start: LayoutPoint(x: node.x, y: node.y),
                segments: path.segments,
                blockStyles: styles,
                blockIDs: blockIDs
            )
        }
        let turnoutTopologies = Dictionary(
            uniqueKeysWithValues: topology.turnoutTopologies.map {
                ($0.turnoutId, $0)
            }
        )
        turnouts = presentation.turnouts.map { turnout in
            let styles = topology.blocks.compactMap {
                block -> LayoutBlockStyle? in
                guard block.turnoutIds?.contains(turnout.turnoutId) == true else {
                    return nil
                }
                return blockStyles[block.id]
            }
            let blockIDs = topology.blocks
                .filter { $0.turnoutIds?.contains(turnout.turnoutId) == true }
                .map(\.id)
            return Turnout(
                presentation: turnout,
                ports: turnoutTopologies[turnout.turnoutId]?.ports.compactMap {
                    guard let position = nodePositions[$0.nodeId] else { return nil }
                    return LayoutPoint(x: position.x, y: position.y)
                } ?? [],
                blockStyles: styles,
                blockIDs: blockIDs
            )
        }
        nodes = presentation.nodes
    }
}

struct TopologyRenderer: View {
    let plan: TopologyRenderPlan
    let transform: LayoutViewportTransform
    let mode: LayoutInteractionMode
    let gridSpacing: Double
    let showsGrid: Bool
    var runtime: TopologyRuntimeState = .empty

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            if showsGrid {
                drawGrid(context: &context, size: size)
            }
            drawBlockOverlays(context: &context)
            drawOccupancy(context: &context)
            drawTracks(context: &context)
            drawTurnouts(context: &context)

            if case .editor(showHandles: true) = mode {
                drawNodes(context: &context)
            }
        }
        .accessibilityLabel("Plan du réseau")
    }

    private func drawOccupancy(context: inout GraphicsContext) {
        for track in plan.tracks {
            switch runtime.occupancyEmphasis(for: track.blockIDs) {
            case .occupied:
                context.stroke(
                    trackPath(track),
                    with: .color(.red.opacity(0.9)),
                    style: StrokeStyle(
                        lineWidth: max(5, 9 * transform.zoom),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            case .unknown:
                context.stroke(
                    trackPath(track),
                    with: .color(.yellow.opacity(0.8)),
                    style: StrokeStyle(
                        lineWidth: max(4, 7 * transform.zoom),
                        lineCap: .round,
                        dash: [6, 5]
                    )
                )
            case .none:
                break
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        guard gridSpacing > 0 else { return }
        let spacing = gridSpacing * transform.zoom
        guard spacing >= 3 else { return }

        var path = Path()
        var x = transform.panX.truncatingRemainder(dividingBy: spacing)
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }

        var y = transform.panY.truncatingRemainder(dividingBy: spacing)
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }

        context.stroke(
            path,
            with: .color(.secondary.opacity(0.16)),
            lineWidth: 1
        )
    }

    private func drawBlockOverlays(context: inout GraphicsContext) {
        for track in plan.tracks {
            let path = trackPath(track)
            for style in track.blockStyles {
                context.stroke(
                    path,
                    with: .color(Color(hex: style.color).opacity(style.opacity)),
                    style: StrokeStyle(
                        lineWidth: 14 * transform.zoom,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    private func drawTracks(context: inout GraphicsContext) {
        for track in plan.tracks {
            context.stroke(
                trackPath(track),
                with: .color(.primary.opacity(0.88)),
                style: StrokeStyle(
                    lineWidth: max(2, 3 * transform.zoom),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func drawTurnouts(context: inout GraphicsContext) {
        for turnout in plan.turnouts {
            let presentation = turnout.presentation
            let center = transform.canvasPoint(
                for: LayoutPoint(x: presentation.x, y: presentation.y)
            )
            let radius = max(5, 7 * transform.zoom)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            for style in turnout.blockStyles {
                context.fill(
                    Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)),
                    with: .color(Color(hex: style.color).opacity(style.opacity))
                )
            }
            var geometry = Path()
            for port in turnout.ports {
                geometry.move(to: center)
                geometry.addLine(
                    to: transform.canvasPoint(for: port)
                )
            }
            context.stroke(
                geometry,
                with: .color(.primary.opacity(0.9)),
                style: StrokeStyle(
                    lineWidth: max(2, 3 * transform.zoom),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(turnoutColor(id: turnout.id))
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.primary),
                lineWidth: max(1, transform.zoom)
            )
        }
    }

    private func turnoutColor(id: String) -> Color {
        switch runtime.turnoutVisualState(for: id) {
        case .unknown:
            return .gray
        case .confirmed:
            return .green
        case .transitioning:
            return .yellow
        case .inconsistent:
            return .orange
        case .failed:
            return .red
        }
    }

    private func drawNodes(context: inout GraphicsContext) {
        for node in plan.nodes {
            let center = transform.canvasPoint(
                for: LayoutPoint(x: node.x, y: node.y)
            )
            let radius = max(3, 4 * transform.zoom)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1)
        }
    }

    private func trackPath(_ track: TopologyRenderPlan.Track) -> Path {
        var path = Path()
        path.move(to: transform.canvasPoint(for: track.start))

        for segment in track.segments {
            switch segment {
            case .line(let point):
                path.addLine(to: transform.canvasPoint(for: point))
            case .cubic(let control1, let control2, let point):
                path.addCurve(
                    to: transform.canvasPoint(for: point),
                    control1: transform.canvasPoint(for: control1),
                    control2: transform.canvasPoint(for: control2)
                )
            }
        }
        return path
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
