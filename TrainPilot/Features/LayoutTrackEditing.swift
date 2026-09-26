import Foundation

enum LayoutTrackValidationIssue: Equatable {
    case duplicateNodeID(String)
    case duplicateTrackSectionID(String)
    case missingNode(sectionID: String, nodeID: String)
    case missingPresentation(String)
    case emptyGeometry(String)
    case nonFiniteCoordinate(String)
    case endpointMismatch(String)
}

struct LayoutTrackValidator {
    func validate(
        topology: TopologyDefinition,
        presentation: LayoutPresentationDefinition
    ) -> [LayoutTrackValidationIssue] {
        var issues: [LayoutTrackValidationIssue] = []
        issues += duplicates(topology.nodes.map(\.id)).map {
            .duplicateNodeID($0)
        }
        issues += duplicates(topology.trackSections.map(\.id)).map {
            .duplicateTrackSectionID($0)
        }

        let nodeIDs = Set(topology.nodes.map(\.id))
        let positions = Dictionary(
            uniqueKeysWithValues: presentation.nodes.map { ($0.nodeId, $0) }
        )
        let paths = Dictionary(
            uniqueKeysWithValues: presentation.trackSections.map {
                ($0.trackSectionId, $0)
            }
        )

        for section in topology.trackSections {
            if !nodeIDs.contains(section.nodeAId) {
                issues.append(.missingNode(sectionID: section.id, nodeID: section.nodeAId))
            }
            if !nodeIDs.contains(section.nodeBId) {
                issues.append(.missingNode(sectionID: section.id, nodeID: section.nodeBId))
            }
            guard let path = paths[section.id] else {
                issues.append(.missingPresentation(section.id))
                continue
            }
            guard !path.segments.isEmpty else {
                issues.append(.emptyGeometry(section.id))
                continue
            }
            if path.segments.contains(where: { !$0.hasFiniteCoordinates }) {
                issues.append(.nonFiniteCoordinate(section.id))
            }
            if let nodeB = positions[section.nodeBId],
               path.segments.last?.endPoint != LayoutPoint(x: nodeB.x, y: nodeB.y) {
                issues.append(.endpointMismatch(section.id))
            }
        }
        return issues
    }

    private func duplicates(_ ids: [String]) -> [String] {
        Dictionary(grouping: ids, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }
}

extension LayoutEditorController {
    @discardableResult
    func addTrackSection(
        id: String = UUID().uuidString,
        name: String = "Nouvelle section",
        start: LayoutPoint,
        intermediatePoints: [LayoutPoint] = [],
        end: LayoutPoint,
        transform: LayoutViewportTransform,
        snapEnabled: Bool,
        optionKeyPressed: Bool,
        connectionToleranceCanvas: Double = 10
    ) -> String {
        let spacing = document.presentation.gridSpacing
        let snappedStart = transform.snapped(
            start,
            gridSpacing: spacing,
            enabled: snapEnabled && !optionKeyPressed
        )
        let snappedEnd = transform.snapped(
            end,
            gridSpacing: spacing,
            enabled: snapEnabled && !optionKeyPressed
        )
        let tolerance = connectionToleranceCanvas / transform.zoom

        var topology = document.topology
        var presentation = document.presentation
        let startNodeID = resolveNode(
            near: snappedStart,
            tolerance: tolerance,
            topology: &topology,
            presentation: &presentation
        )
        let endNodeID = resolveNode(
            near: snappedEnd,
            tolerance: tolerance,
            topology: &topology,
            presentation: &presentation
        )
        let points = intermediatePoints.map {
            transform.snapped(
                $0,
                gridSpacing: spacing,
                enabled: snapEnabled && !optionKeyPressed
            )
        } + [snappedEnd]
        let path = LayoutTrackPath(
            trackSectionId: id,
            segments: points.map { .line(to: $0) }
        )
        topology = topology.replacing(
            trackSections: topology.trackSections + [
                TrackSection(
                    id: id,
                    name: name,
                    nodeAId: startNodeID,
                    nodeBId: endNodeID,
                    lengthMm: nil
                )
            ]
        )
        presentation = presentation.replacing(
            trackSections: presentation.trackSections + [path]
        )

        performMutation {
            document.replaceSnapshot(
                LayoutSnapshot(topology: topology, presentation: presentation)
            )
        }
        select(.trackSection(id))
        return id
    }

    func convertTrackSegmentToCubic(sectionID: String, segmentIndex: Int) throws {
        guard let section = document.topology.trackSections.first(where: {
            $0.id == sectionID
        }),
        let startNode = document.presentation.nodes.first(where: {
            $0.nodeId == section.nodeAId
        }),
        let pathIndex = document.presentation.trackSections.firstIndex(where: {
            $0.trackSectionId == sectionID
        }) else {
            throw LayoutEditError.missingResource(sectionID)
        }

        var paths = document.presentation.trackSections
        var segments = paths[pathIndex].segments
        guard segments.indices.contains(segmentIndex) else {
            throw LayoutEditError.missingResource("\(sectionID)[\(segmentIndex)]")
        }
        let start = segmentIndex == 0
            ? LayoutPoint(x: startNode.x, y: startNode.y)
            : segments[segmentIndex - 1].endPoint
        let end = segments[segmentIndex].endPoint
        let deltaX = (end.x - start.x) / 3
        let deltaY = (end.y - start.y) / 3
        segments[segmentIndex] = .cubic(
            control1: LayoutPoint(x: start.x + deltaX, y: start.y + deltaY),
            control2: LayoutPoint(x: start.x + deltaX * 2, y: start.y + deltaY * 2),
            to: end
        )
        paths[pathIndex] = LayoutTrackPath(
            trackSectionId: sectionID,
            segments: segments
        )
        performMutation {
            document.replacePresentation(document.presentation.replacing(trackSections: paths))
        }
    }

    func convertTrackSegmentToLine(sectionID: String, segmentIndex: Int) throws {
        try updateTrackSegment(sectionID: sectionID, segmentIndex: segmentIndex) {
            .line(to: $0.endPoint)
        }
    }

    func moveBezierControl(
        sectionID: String,
        segmentIndex: Int,
        controlIndex: Int,
        to point: LayoutPoint,
        transform: LayoutViewportTransform,
        snapEnabled: Bool,
        optionKeyPressed: Bool
    ) throws {
        let destination = transform.snapped(
            point,
            gridSpacing: document.presentation.gridSpacing,
            enabled: snapEnabled && !optionKeyPressed
        )
        try updateTrackSegment(sectionID: sectionID, segmentIndex: segmentIndex) { segment in
            guard case .cubic(let control1, let control2, let end) = segment else {
                return segment
            }
            return .cubic(
                control1: controlIndex == 1 ? destination : control1,
                control2: controlIndex == 2 ? destination : control2,
                to: end
            )
        }
    }

    func graphicalLength(of sectionID: String) -> Double? {
        guard let section = document.topology.trackSections.first(where: {
            $0.id == sectionID
        }),
        let node = document.presentation.nodes.first(where: {
            $0.nodeId == section.nodeAId
        }),
        let path = document.presentation.trackSections.first(where: {
            $0.trackSectionId == sectionID
        }) else {
            return nil
        }

        var current = LayoutPoint(x: node.x, y: node.y)
        var length = 0.0
        for segment in path.segments {
            switch segment {
            case .line(let end):
                length += current.distance(to: end)
            case .cubic(let control1, let control2, let end):
                var previous = current
                for step in 1...20 {
                    let t = Double(step) / 20
                    let point = LayoutPoint.cubic(
                        from: current,
                        control1: control1,
                        control2: control2,
                        to: end,
                        t: t
                    )
                    length += previous.distance(to: point)
                    previous = point
                }
            }
            current = segment.endPoint
        }
        return length
    }

    private func resolveNode(
        near point: LayoutPoint,
        tolerance: Double,
        topology: inout TopologyDefinition,
        presentation: inout LayoutPresentationDefinition
    ) -> String {
        if let existing = presentation.nodes
            .filter({ LayoutPoint(x: $0.x, y: $0.y).distance(to: point) <= tolerance })
            .sorted(by: { $0.nodeId < $1.nodeId })
            .first {
            return existing.nodeId
        }

        let id = UUID().uuidString
        topology = topology.replacing(
            nodes: topology.nodes + [TopologyNode(id: id, name: nil, kind: .joint)]
        )
        presentation = presentation.replacing(
            nodes: presentation.nodes + [
                LayoutNodePosition(nodeId: id, x: point.x, y: point.y)
            ]
        )
        return id
    }

    private func updateTrackSegment(
        sectionID: String,
        segmentIndex: Int,
        transform: (LayoutTrackSegment) -> LayoutTrackSegment
    ) throws {
        guard let pathIndex = document.presentation.trackSections.firstIndex(where: {
            $0.trackSectionId == sectionID
        }) else {
            throw LayoutEditError.missingResource(sectionID)
        }
        var paths = document.presentation.trackSections
        var segments = paths[pathIndex].segments
        guard segments.indices.contains(segmentIndex) else {
            throw LayoutEditError.missingResource("\(sectionID)[\(segmentIndex)]")
        }
        segments[segmentIndex] = transform(segments[segmentIndex])
        paths[pathIndex] = LayoutTrackPath(
            trackSectionId: sectionID,
            segments: segments
        )
        performMutation {
            document.replacePresentation(document.presentation.replacing(trackSections: paths))
        }
    }
}

extension LayoutTrackSegment {
    var endPoint: LayoutPoint {
        switch self {
        case .line(let point), .cubic(_, _, let point): return point
        }
    }

    var hasFiniteCoordinates: Bool {
        switch self {
        case .line(let point):
            return point.isFinite
        case .cubic(let control1, let control2, let point):
            return control1.isFinite && control2.isFinite && point.isFinite
        }
    }
}

extension LayoutPoint {
    var isFinite: Bool { x.isFinite && y.isFinite }

    func distance(to other: LayoutPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }

    static func cubic(
        from start: LayoutPoint,
        control1: LayoutPoint,
        control2: LayoutPoint,
        to end: LayoutPoint,
        t: Double
    ) -> LayoutPoint {
        let oneMinusT = 1 - t
        return LayoutPoint(
            x: oneMinusT * oneMinusT * oneMinusT * start.x
                + 3 * oneMinusT * oneMinusT * t * control1.x
                + 3 * oneMinusT * t * t * control2.x
                + t * t * t * end.x,
            y: oneMinusT * oneMinusT * oneMinusT * start.y
                + 3 * oneMinusT * oneMinusT * t * control1.y
                + 3 * oneMinusT * t * t * control2.y
                + t * t * t * end.y
        )
    }
}
