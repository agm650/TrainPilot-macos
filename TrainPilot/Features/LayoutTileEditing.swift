import Foundation

enum LayoutTileProfile: String, CaseIterable, Identifiable {
    case straight, curve, leftTurnout, rightTurnout, threeWay, doubleSlip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: return "Droite"
        case .curve: return "Courbe"
        case .leftTurnout: return "Aiguille gauche"
        case .rightTurnout: return "Aiguille droite"
        case .threeWay: return "Triple"
        case .doubleSlip: return "TJD"
        }
    }

    var turnoutKind: TurnoutKind? {
        switch self {
        case .leftTurnout, .rightTurnout: return .simple
        case .threeWay: return .threeWay
        case .doubleSlip: return .doubleSlip
        default: return nil
        }
    }

    // Normalized ports lie on cell edges. All rotations retain a one-cell footprint.
    var ports: [LayoutPoint] {
        switch self {
        case .straight: return [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)]
        case .curve: return [.init(x: 0, y: 0.5), .init(x: 0.5, y: 0)]
        case .leftTurnout:
            return [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5), .init(x: 1, y: 0)]
        case .rightTurnout:
            return [.init(x: 0, y: 0.5), .init(x: 1, y: 0.5), .init(x: 1, y: 1)]
        case .threeWay:
            return [.init(x: 0, y: 0.5), .init(x: 1, y: 0),
                    .init(x: 1, y: 0.5), .init(x: 1, y: 1)]
        case .doubleSlip:
            return [.init(x: 0, y: 0), .init(x: 1, y: 0),
                    .init(x: 0, y: 1), .init(x: 1, y: 1)]
        }
    }

    func point(_ point: LayoutPoint, rotationSteps: Int) -> LayoutPoint {
        let steps = (rotationSteps % 8 + 8) % 8
        var result = point
        for _ in 0..<(steps / 2) {
            result = LayoutPoint(x: 1 - result.y, y: result.x)
        }
        guard steps % 2 != 0 else { return result }

        // Rotate 45° and preserve distance to the square boundary rather than
        // the circle radius: edge midpoints become corners and vice versa.
        // This also keeps radial Bézier handles tangent to adjoining rails.
        let x = result.x - 0.5
        let y = result.y - 0.5
        let rotatedX = x - y
        let rotatedY = x + y
        let extent = max(abs(rotatedX), abs(rotatedY))
        guard extent > 0 else { return result }
        let scale = max(abs(x), abs(y)) / extent
        return LayoutPoint(x: 0.5 + rotatedX * scale, y: 0.5 + rotatedY * scale)
    }
}

enum LayoutTileError: LocalizedError {
    case occupied
    case invalidGrid
    case connectedEquipment

    var errorDescription: String? {
        switch self {
        case .connectedEquipment: return "Déconnectez les voies voisines avant de tourner cet équipement."
        case .occupied: return "Cette case contient déjà une voie ou un équipement."
        case .invalidGrid: return "Le pas de la grille doit être un nombre positif."
        }
    }
}

extension LayoutEditorController {
    func selectTile(_ profile: LayoutTileProfile) {
        tileProfile = profile
        tilePlacementMessage = nil
        selectTool(.tile)
    }

    func placeTile(at location: LayoutPoint) throws {
        let spacing = document.presentation.gridSpacing
        guard spacing.isFinite, spacing > 0, location.x.isFinite, location.y.isFinite else {
            throw LayoutTileError.invalidGrid
        }
        let origin = LayoutPoint(
            x: floor(location.x / spacing) * spacing,
            y: floor(location.y / spacing) * spacing
        )
        guard !tileCellIsOccupied(origin: origin, spacing: spacing) else {
            throw LayoutTileError.occupied
        }
        let profile = tileProfile
        func placed(_ point: LayoutPoint) -> LayoutPoint {
            let rotated = profile.point(point, rotationSteps: tileRotationSteps)
            return LayoutPoint(x: origin.x + rotated.x * spacing, y: origin.y + rotated.y * spacing)
        }

        var nodes = document.topology.nodes
        var positions = document.presentation.nodes
        let nodeIDs = profile.ports.map { port -> String in
            let point = placed(port)
            // Reuse only ordinary joints, never a buffer or an external boundary.
            if let existing = positions.first(where: { position in
                abs(position.x - point.x) < 0.000001 && abs(position.y - point.y) < 0.000001 &&
                nodes.contains(where: { node in node.id == position.nodeId && node.kind == .joint })
            }) {
                return existing.nodeId
            }
            let id = UUID().uuidString
            nodes.append(TopologyNode(id: id, name: nil, kind: .joint))
            positions.append(LayoutNodePosition(nodeId: id, x: point.x, y: point.y))
            return id
        }

        let id = UUID().uuidString
        var topology = document.topology.replacing(nodes: nodes)
        var presentation = document.presentation.replacing(nodes: positions)
        var definitions = document.turnoutDefinitions
        let newSelection: LayoutEditorSelection

        if let kind = profile.turnoutKind {
            let address = (definitions.flatMap(\.endpoints).map(\.linearAddress).max() ?? 0) + 1
            let template = TurnoutTemplate(kind: kind, firstAddress: address)
            let ports = zip(template.portIDs, nodeIDs).map { TurnoutPort(id: $0, nodeId: $1) }
            topology = topology.replacing(turnoutTopologies: topology.turnoutTopologies + [
                TurnoutTopology(turnoutId: id, ports: ports, positions: template.topologyPositions)
            ])
            presentation = presentation.replacing(turnouts: presentation.turnouts + [
                LayoutTurnoutPresentation(
                    turnoutId: id, x: origin.x + spacing / 2, y: origin.y + spacing / 2,
                    rotationDegrees: Double(((tileRotationSteps % 8 + 8) % 8) * 45), mirrored: profile == .leftTurnout
                )
            ])
            definitions.append(TurnoutDefinition(
                id: id, name: profile.title, kind: kind,
                endpoints: template.endpoints, positions: template.logicalPositions
            ))
            newSelection = .turnout(id)
        } else {
            let segment: LayoutTrackSegment
            if profile == .curve {
                // Quarter circle of radius half a cell, with tangent continuity at each edge.
                segment = .cubic(
                    control1: placed(LayoutPoint(x: 0.2761423749, y: 0.5)),
                    control2: placed(LayoutPoint(x: 0.5, y: 0.2761423749)),
                    to: placed(profile.ports[1])
                )
            } else {
                segment = .line(to: placed(profile.ports[1]))
            }
            topology = topology.replacing(trackSections: topology.trackSections + [
                TrackSection(id: id, name: profile.title, nodeAId: nodeIDs[0], nodeBId: nodeIDs[1], lengthMm: nil)
            ])
            presentation = presentation.replacing(trackSections: presentation.trackSections + [
                LayoutTrackPath(trackSectionId: id, segments: [segment])
            ])
            newSelection = .trackSection(id)
        }
        performMutation {
            document.replaceEditingState(
                snapshot: LayoutSnapshot(topology: topology, presentation: presentation),
                turnoutDefinitions: definitions
            )
        }
        select(newSelection)
        tilePlacementMessage = nil
    }

    private func tileCellIsOccupied(origin: LayoutPoint, spacing: Double) -> Bool {
        func inside(_ point: LayoutPoint) -> Bool {
            let epsilon = spacing * 0.000001
            return point.x > origin.x + epsilon && point.x < origin.x + spacing - epsilon &&
                point.y > origin.y + epsilon && point.y < origin.y + spacing - epsilon
        }
        // Test line/rectangle intersection too, so long imported segments cannot skip a cell.
        func intersects(_ a: LayoutPoint, _ b: LayoutPoint) -> Bool {
            let epsilon = spacing * 0.000001
            var lower = 0.0
            var upper = 1.0
            for (start, delta, minimum, maximum) in [
                (a.x, b.x - a.x, origin.x + epsilon, origin.x + spacing - epsilon),
                (a.y, b.y - a.y, origin.y + epsilon, origin.y + spacing - epsilon)
            ] {
                if abs(delta) < 1e-12 {
                    if start < minimum || start > maximum { return false }
                } else {
                    let first = (minimum - start) / delta
                    let last = (maximum - start) / delta
                    lower = max(lower, min(first, last))
                    upper = min(upper, max(first, last))
                    if lower > upper { return false }
                }
            }
            return true
        }
        let plan = TopologyRenderPlan(topology: document.topology, presentation: document.presentation)
        for turnout in plan.turnouts {
            let center = LayoutPoint(x: turnout.presentation.x, y: turnout.presentation.y)
            if inside(center) || turnout.ports.contains(where: { intersects(center, $0) }) { return true }
        }
        for track in plan.tracks {
            var current = track.start
            for segment in track.segments {
                let samples = segment.sampledPoints(from: current)
                if zip(samples, samples.dropFirst()).contains(where: { intersects($0, $1) }) { return true }
                current = segment.endPoint
            }
        }
        return false
    }
}
