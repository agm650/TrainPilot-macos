import Combine
import Foundation

enum LayoutEditorTool: String, CaseIterable, Equatable {
    case select
    case track
    case turnout
    case block
}

enum LayoutEditorSelection: Equatable {
    case trackSection(String)
    case turnout(String)
    case block(String)
    case node(String)
}

enum LayoutInspectorState: Equatable {
    case noSelection
    case trackSection(String)
    case turnout(String)
    case block(String)
    case node(String)
}

enum LayoutEditError: LocalizedError, Equatable {
    case missingResource(String)
    case referencedByBlocks([String])
    case referencedByTrackSections([String])

    var errorDescription: String? {
        switch self {
        case .missingResource(let id):
            return "La ressource \(id) n’existe plus."
        case .referencedByBlocks(let ids):
            return "Suppression impossible : référence par les blocks \(ids.joined(separator: ", "))."
        case .referencedByTrackSections(let ids):
            return "Suppression impossible : référence par les sections \(ids.joined(separator: ", "))."
        }
    }
}

private struct LayoutEditCommand {
    let before: LayoutEditorState
    let after: LayoutEditorState
}

struct LayoutEditorState: Equatable, Sendable {
    let snapshot: LayoutSnapshot
    let turnoutDefinitions: [TurnoutDefinition]
}

@MainActor
final class LayoutEditorController: ObservableObject {
    @Published private(set) var tool: LayoutEditorTool = .select
    @Published private(set) var selection: LayoutEditorSelection?
    @Published private(set) var inspectorState: LayoutInspectorState = .noSelection

    let document: LayoutEditorDocument

    private var undoStack: [LayoutEditCommand] = []
    private var redoStack: [LayoutEditCommand] = []
    private var dragStartSnapshot: LayoutEditorState?

    init(document: LayoutEditorDocument) {
        self.document = document
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func selectTool(_ tool: LayoutEditorTool) {
        self.tool = tool
        if tool != .select {
            select(nil)
        }
    }

    func select(_ selection: LayoutEditorSelection?) {
        self.selection = selection
        inspectorState = selection.map(LayoutInspectorState.init) ?? .noSelection
    }

    func beginDrag() {
        guard dragStartSnapshot == nil else { return }
        dragStartSnapshot = currentState
    }

    func moveSelection(
        to point: LayoutPoint,
        transform: LayoutViewportTransform,
        gridSpacing: Double,
        snapEnabled: Bool,
        optionKeyPressed: Bool
    ) throws {
        let destination = transform.snapped(
            point,
            gridSpacing: gridSpacing,
            enabled: snapEnabled && !optionKeyPressed
        )

        guard let selection else { return }
        switch selection {
        case .node(let id):
            try moveNode(id: id, to: destination)
        case .turnout(let id):
            try moveTurnout(id: id, to: destination)
        case .trackSection, .block:
            return
        }
    }

    func endDrag() {
        guard let before = dragStartSnapshot else { return }
        dragStartSnapshot = nil
        record(before: before, after: currentState)
    }

    func cancelDrag() {
        guard let before = dragStartSnapshot else { return }
        dragStartSnapshot = nil
        document.replaceEditingState(
            snapshot: before.snapshot,
            turnoutDefinitions: before.turnoutDefinitions
        )
    }

    func performMutation(_ mutation: () throws -> Void) rethrows {
        let before = currentState
        try mutation()
        record(before: before, after: currentState)
    }

    func deleteSelection() throws {
        guard let selection else { return }
        let before = currentState

        switch selection {
        case .trackSection(let id):
            try deleteTrackSection(id: id)
        case .turnout(let id):
            try deleteTurnout(id: id)
        case .block(let id):
            deleteBlock(id: id)
        case .node(let id):
            try deleteNode(id: id)
        }

        select(nil)
        record(before: before, after: currentState)
    }

    func undo() {
        guard let command = undoStack.popLast() else { return }
        redoStack.append(command)
        document.replaceEditingState(
            snapshot: command.before.snapshot,
            turnoutDefinitions: command.before.turnoutDefinitions
        )
        validateSelection()
    }

    func redo() {
        guard let command = redoStack.popLast() else { return }
        undoStack.append(command)
        document.replaceEditingState(
            snapshot: command.after.snapshot,
            turnoutDefinitions: command.after.turnoutDefinitions
        )
        validateSelection()
    }

    private var currentState: LayoutEditorState {
        LayoutEditorState(
            snapshot: LayoutSnapshot(
                topology: document.topology,
                presentation: document.presentation
            ),
            turnoutDefinitions: document.turnoutDefinitions
        )
    }

    private func record(before: LayoutEditorState, after: LayoutEditorState) {
        guard before != after else { return }
        undoStack.append(LayoutEditCommand(before: before, after: after))
        redoStack.removeAll()
    }

    private func moveNode(id: String, to point: LayoutPoint) throws {
        guard document.presentation.nodes.contains(where: { $0.nodeId == id }) else {
            throw LayoutEditError.missingResource(id)
        }

        let nodes = document.presentation.nodes.map { node in
            node.nodeId == id
                ? LayoutNodePosition(nodeId: id, x: point.x, y: point.y)
                : node
        }
        let sectionByID = Dictionary(
            uniqueKeysWithValues: document.topology.trackSections.map { ($0.id, $0) }
        )
        let paths = document.presentation.trackSections.map { path -> LayoutTrackPath in
            guard sectionByID[path.trackSectionId]?.nodeBId == id,
                  !path.segments.isEmpty else {
                return path
            }
            var segments = path.segments
            segments[segments.count - 1] = segments[segments.count - 1]
                .replacingEndPoint(with: point)
            return LayoutTrackPath(trackSectionId: path.trackSectionId, segments: segments)
        }

        document.replacePresentation(
            document.presentation.replacing(nodes: nodes, trackSections: paths)
        )
    }

    private func moveTurnout(id: String, to point: LayoutPoint) throws {
        guard document.presentation.turnouts.contains(where: { $0.turnoutId == id }) else {
            throw LayoutEditError.missingResource(id)
        }
        let turnouts = document.presentation.turnouts.map { turnout in
            turnout.turnoutId == id
                ? LayoutTurnoutPresentation(
                    turnoutId: id,
                    x: point.x,
                    y: point.y,
                    rotationDegrees: turnout.rotationDegrees,
                    mirrored: turnout.mirrored
                )
                : turnout
        }
        document.replacePresentation(document.presentation.replacing(turnouts: turnouts))
    }

    private func deleteTrackSection(id: String) throws {
        let blockIDs = document.topology.blocks
            .filter { $0.trackSectionIds.contains(id) }
            .map(\.id)
        guard blockIDs.isEmpty else {
            throw LayoutEditError.referencedByBlocks(blockIDs)
        }
        guard document.topology.trackSections.contains(where: { $0.id == id }) else {
            throw LayoutEditError.missingResource(id)
        }
        document.replaceSnapshot(
            LayoutSnapshot(
                topology: document.topology.replacing(
                    trackSections: document.topology.trackSections.filter { $0.id != id }
                ),
                presentation: document.presentation.replacing(
                    trackSections: document.presentation.trackSections.filter {
                        $0.trackSectionId != id
                    }
                )
            )
        )
    }

    private func deleteTurnout(id: String) throws {
        let blockIDs = document.topology.blocks
            .filter { $0.turnoutIds?.contains(id) == true }
            .map(\.id)
        guard blockIDs.isEmpty else {
            throw LayoutEditError.referencedByBlocks(blockIDs)
        }
        guard document.topology.turnoutTopologies.contains(where: { $0.turnoutId == id }) else {
            throw LayoutEditError.missingResource(id)
        }
        document.replaceEditingState(
            snapshot: LayoutSnapshot(
                topology: document.topology.replacing(
                    turnoutTopologies: document.topology.turnoutTopologies.filter {
                        $0.turnoutId != id
                    }
                ),
                presentation: document.presentation.replacing(
                    turnouts: document.presentation.turnouts.filter { $0.turnoutId != id }
                )
            ),
            turnoutDefinitions: document.turnoutDefinitions.filter { $0.id != id }
        )
    }

    private func deleteBlock(id: String) {
        document.replaceSnapshot(
            LayoutSnapshot(
                topology: document.topology.replacing(
                    blocks: document.topology.blocks.filter { $0.id != id }
                ),
                presentation: document.presentation.replacing(
                    blocks: document.presentation.blocks.filter { $0.blockId != id }
                )
            )
        )
    }

    private func deleteNode(id: String) throws {
        let references = document.topology.trackSections
            .filter { $0.nodeAId == id || $0.nodeBId == id }
            .map(\.id)
        guard references.isEmpty else {
            throw LayoutEditError.referencedByTrackSections(references)
        }
        document.replaceSnapshot(
            LayoutSnapshot(
                topology: document.topology.replacing(
                    nodes: document.topology.nodes.filter { $0.id != id }
                ),
                presentation: document.presentation.replacing(
                    nodes: document.presentation.nodes.filter { $0.nodeId != id }
                )
            )
        )
    }

    private func validateSelection() {
        guard let selection else { return }
        let exists: Bool
        switch selection {
        case .trackSection(let id):
            exists = document.topology.trackSections.contains { $0.id == id }
        case .turnout(let id):
            exists = document.topology.turnoutTopologies.contains { $0.turnoutId == id }
        case .block(let id):
            exists = document.topology.blocks.contains { $0.id == id }
        case .node(let id):
            exists = document.topology.nodes.contains { $0.id == id }
        }
        if !exists { select(nil) }
    }
}

private extension LayoutInspectorState {
    init(_ selection: LayoutEditorSelection) {
        switch selection {
        case .trackSection(let id): self = .trackSection(id)
        case .turnout(let id): self = .turnout(id)
        case .block(let id): self = .block(id)
        case .node(let id): self = .node(id)
        }
    }
}

extension LayoutTrackSegment {
    func replacingEndPoint(with point: LayoutPoint) -> LayoutTrackSegment {
        switch self {
        case .line:
            return .line(to: point)
        case .cubic(let control1, let control2, _):
            return .cubic(control1: control1, control2: control2, to: point)
        }
    }
}

extension TopologyDefinition {
    func replacing(
        nodes: [TopologyNode]? = nil,
        trackSections: [TrackSection]? = nil,
        turnoutTopologies: [TurnoutTopology]? = nil,
        blocks: [BlockDefinition]? = nil
    ) -> TopologyDefinition {
        TopologyDefinition(
            revision: revision,
            nodes: nodes ?? self.nodes,
            trackSections: trackSections ?? self.trackSections,
            turnoutTopologies: turnoutTopologies ?? self.turnoutTopologies,
            blocks: blocks ?? self.blocks
        )
    }
}

extension LayoutPresentationDefinition {
    func replacing(
        nodes: [LayoutNodePosition]? = nil,
        trackSections: [LayoutTrackPath]? = nil,
        turnouts: [LayoutTurnoutPresentation]? = nil,
        blocks: [LayoutBlockStyle]? = nil
    ) -> LayoutPresentationDefinition {
        LayoutPresentationDefinition(
            revision: revision,
            coordinateSystem: coordinateSystem,
            gridSpacing: gridSpacing,
            nodes: nodes ?? self.nodes,
            trackSections: trackSections ?? self.trackSections,
            turnouts: turnouts ?? self.turnouts,
            blocks: blocks ?? self.blocks
        )
    }
}
