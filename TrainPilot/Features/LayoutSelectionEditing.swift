import Foundation

struct LayoutSelectionMover {
    func moved(
        _ state: LayoutEditorState,
        selection: Set<LayoutEditorSelection>,
        delta: LayoutPoint,
        identifier: String
    ) -> LayoutEditorState {
        guard delta.x != 0 || delta.y != 0 else { return state }
        let topology = state.snapshot.topology
        let presentation = state.snapshot.presentation
        let tracks = topology.trackSections.filter { selection.contains(.trackSection($0.id)) }
        let turnouts = topology.turnoutTopologies.filter { selection.contains(.turnout($0.turnoutId)) }
        let movedNodes = Set(tracks.flatMap { [$0.nodeAId, $0.nodeBId] })
            .union(turnouts.flatMap { $0.ports.map(\.nodeId) })
        let externalNodes = Set(topology.trackSections
            .filter { !selection.contains(.trackSection($0.id)) }
            .flatMap { [$0.nodeAId, $0.nodeBId] })
            .union(topology.turnoutTopologies
                .filter { !selection.contains(.turnout($0.turnoutId)) }
                .flatMap { $0.ports.map(\.nodeId) })
        let sharedNodes = movedNodes.intersection(externalNodes)
        func movedID(_ id: String) -> String {
            sharedNodes.contains(id) ? "\(id)-\(identifier)" : id
        }
        func translated(_ point: LayoutPoint) -> LayoutPoint {
            LayoutPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        let nodes = topology.nodes.flatMap { node -> [TopologyNode] in
            guard sharedNodes.contains(node.id) else { return [node] }
            return [node, TopologyNode(id: movedID(node.id), name: node.name, kind: node.kind)]
        }
        let positions = presentation.nodes.flatMap { node -> [LayoutNodePosition] in
            guard movedNodes.contains(node.nodeId) else { return [node] }
            let moved = LayoutNodePosition(
                nodeId: movedID(node.nodeId), x: node.x + delta.x, y: node.y + delta.y
            )
            return sharedNodes.contains(node.nodeId) ? [node, moved] : [moved]
        }
        let sections = topology.trackSections.map { section -> TrackSection in
            guard selection.contains(.trackSection(section.id)) else { return section }
            return TrackSection(
                id: section.id, name: section.name,
                nodeAId: movedID(section.nodeAId), nodeBId: movedID(section.nodeBId),
                lengthMm: section.lengthMm
            )
        }
        let turnoutTopologies = topology.turnoutTopologies.map { turnout -> TurnoutTopology in
            guard selection.contains(.turnout(turnout.turnoutId)) else { return turnout }
            return TurnoutTopology(
                turnoutId: turnout.turnoutId,
                ports: turnout.ports.map { TurnoutPort(id: $0.id, nodeId: movedID($0.nodeId)) },
                positions: turnout.positions
            )
        }
        let paths = presentation.trackSections.map { path -> LayoutTrackPath in
            guard selection.contains(.trackSection(path.trackSectionId)) else { return path }
            return LayoutTrackPath(trackSectionId: path.trackSectionId, segments: path.segments.map {
                switch $0 {
                case .line(let end): return .line(to: translated(end))
                case .cubic(let first, let second, let end):
                    return .cubic(control1: translated(first), control2: translated(second), to: translated(end))
                }
            })
        }
        let turnoutPositions = presentation.turnouts.map { turnout -> LayoutTurnoutPresentation in
            guard selection.contains(.turnout(turnout.turnoutId)) else { return turnout }
            return LayoutTurnoutPresentation(
                turnoutId: turnout.turnoutId, x: turnout.x + delta.x, y: turnout.y + delta.y,
                rotationDegrees: turnout.rotationDegrees, mirrored: turnout.mirrored
            )
        }
        return LayoutEditorState(
            snapshot: LayoutSnapshot(
                topology: topology.replacing(nodes: nodes, trackSections: sections, turnoutTopologies: turnoutTopologies),
                presentation: presentation.replacing(nodes: positions, trackSections: paths, turnouts: turnoutPositions)
            ),
            turnoutDefinitions: state.turnoutDefinitions
        )
    }
}

extension LayoutEditorController {
    func elements(inRectangleFrom start: LayoutPoint, to end: LayoutPoint) -> Set<LayoutEditorSelection> {
        func contains(_ point: LayoutPoint) -> Bool {
            point.x >= min(start.x, end.x) && point.x <= max(start.x, end.x) &&
                point.y >= min(start.y, end.y) && point.y <= max(start.y, end.y)
        }
        let plan = TopologyRenderPlan(topology: document.topology, presentation: document.presentation)
        var result: Set<LayoutEditorSelection> = []
        for track in plan.tracks {
            var points = [track.start]
            var current = track.start
            for segment in track.segments {
                points += segment.sampledPoints(from: current)
                current = segment.endPoint
            }
            if points.allSatisfy(contains) { result.insert(.trackSection(track.id)) }
        }
        for turnout in plan.turnouts {
            if contains(LayoutPoint(x: turnout.presentation.x, y: turnout.presentation.y)) &&
                turnout.ports.allSatisfy(contains) {
                result.insert(.turnout(turnout.id))
            }
        }
        return result
    }

    func updateSelectionDrag(delta: LayoutPoint, snapEnabled: Bool) {
        guard let before = dragStartSnapshot else { return }
        let snapped = LayoutViewportTransform().snapped(
            delta, gridSpacing: before.snapshot.presentation.gridSpacing, enabled: snapEnabled
        )
        let after = LayoutSelectionMover().moved(
            before, selection: selectedElements, delta: snapped, identifier: movementIdentifier
        )
        document.replaceEditingState(snapshot: after.snapshot, turnoutDefinitions: after.turnoutDefinitions)
    }
}
