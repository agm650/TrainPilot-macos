import XCTest
@testable import TrainPilot

@MainActor
final class LayoutEditorControllerTests: XCTestCase {
    func testSelectionAndDeselectionSynchronizeInspector() {
        let controller = makeController()

        controller.select(.trackSection("s1"))
        XCTAssertEqual(controller.inspectorState, .trackSection("s1"))

        controller.select(nil)
        XCTAssertEqual(controller.inspectorState, .noSelection)
    }

    func testWholeDragCreatesOneUndoCommand() throws {
        let controller = makeController()
        controller.select(.node("n1"))
        controller.beginDrag()
        try controller.moveSelection(
            to: LayoutPoint(x: 23, y: 36),
            transform: LayoutViewportTransform(),
            gridSpacing: 10,
            snapEnabled: true,
            optionKeyPressed: false
        )
        try controller.moveSelection(
            to: LayoutPoint(x: 47, y: 61),
            transform: LayoutViewportTransform(),
            gridSpacing: 10,
            snapEnabled: true,
            optionKeyPressed: false
        )
        controller.endDrag()

        XCTAssertTrue(controller.canUndo)
        XCTAssertEqual(controller.document.presentation.nodes[0].x, 50)
        controller.undo()
        XCTAssertEqual(controller.document.presentation.nodes[0].x, 0)
        XCTAssertTrue(controller.canRedo)
        controller.redo()
        XCTAssertEqual(controller.document.presentation.nodes[0].x, 50)
    }

    func testOptionBypassesSnap() throws {
        let controller = makeController()
        controller.select(.node("n1"))
        controller.beginDrag()
        try controller.moveSelection(
            to: LayoutPoint(x: 23, y: 36),
            transform: LayoutViewportTransform(),
            gridSpacing: 10,
            snapEnabled: true,
            optionKeyPressed: true
        )
        controller.endDrag()

        XCTAssertEqual(controller.document.presentation.nodes[0].x, 23)
        XCTAssertEqual(controller.document.presentation.nodes[0].y, 36)
    }

    func testUndoToSavedStateClearsDirtyFlag() throws {
        let controller = makeController()
        controller.select(.turnout("t1"))
        controller.beginDrag()
        try controller.moveSelection(
            to: LayoutPoint(x: 70, y: 80),
            transform: LayoutViewportTransform(),
            gridSpacing: 10,
            snapEnabled: false,
            optionKeyPressed: false
        )
        controller.endDrag()

        XCTAssertTrue(controller.document.isDirty)
        controller.undo()
        XCTAssertFalse(controller.document.isDirty)
    }

    func testReferencedTrackCannotBeDeleted() {
        let controller = makeController()
        controller.select(.trackSection("s1"))

        XCTAssertThrowsError(try controller.deleteSelection()) { error in
            XCTAssertEqual(error as? LayoutEditError, .referencedByBlocks(["b1"]))
        }
        XCTAssertEqual(controller.selection, .trackSection("s1"))
    }

    func testDeleteBlockCanBeUndoneAndRedone() throws {
        let controller = makeController()
        controller.select(.block("b1"))

        try controller.deleteSelection()
        XCTAssertTrue(controller.document.topology.blocks.isEmpty)
        XCTAssertNil(controller.selection)

        controller.undo()
        XCTAssertEqual(controller.document.topology.blocks.count, 1)
        controller.redo()
        XCTAssertTrue(controller.document.topology.blocks.isEmpty)
    }

    func testEmptyHistoryIsSafe() {
        let controller = makeController()
        controller.undo()
        controller.redo()
        XCTAssertFalse(controller.canUndo)
        XCTAssertFalse(controller.canRedo)
    }

    private func makeController() -> LayoutEditorController {
        let snapshot = LayoutSnapshot(
            topology: TopologyDefinition(
                revision: "topology-1",
                nodes: [
                    TopologyNode(id: "n1", name: nil, kind: .joint),
                    TopologyNode(id: "n2", name: nil, kind: .joint)
                ],
                trackSections: [
                    TrackSection(
                        id: "s1", name: "Section", nodeAId: "n1",
                        nodeBId: "n2", lengthMm: nil
                    )
                ],
                turnoutTopologies: [
                    TurnoutTopology(turnoutId: "t1", ports: [], positions: [])
                ],
                blocks: [
                    BlockDefinition(
                        id: "b1", name: "Block", trackSectionIds: ["s1"],
                        turnoutIds: []
                    )
                ]
            ),
            presentation: LayoutPresentationDefinition(
                revision: "presentation-1",
                coordinateSystem: "layout-units",
                gridSpacing: 10,
                nodes: [
                    LayoutNodePosition(nodeId: "n1", x: 0, y: 0),
                    LayoutNodePosition(nodeId: "n2", x: 100, y: 0)
                ],
                trackSections: [
                    LayoutTrackPath(
                        trackSectionId: "s1",
                        segments: [.line(to: LayoutPoint(x: 100, y: 0))]
                    )
                ],
                turnouts: [
                    LayoutTurnoutPresentation(
                        turnoutId: "t1", x: 20, y: 20,
                        rotationDegrees: 0, mirrored: false
                    )
                ],
                blocks: [
                    LayoutBlockStyle(blockId: "b1", color: "#FF0000", opacity: 0.4)
                ]
            )
        )
        let document = LayoutEditorDocument(
            serverIdentity: "server",
            snapshot: snapshot,
            draftStore: LayoutDraftStoreSpyForController(),
            autosaveDelayNanoseconds: 10_000_000_000
        )
        return LayoutEditorController(document: document)
    }
}

private actor LayoutDraftStoreSpyForController: LayoutDraftStoring {
    func load(serverIdentity: String) -> LayoutDraft? { nil }
    func save(_ draft: LayoutDraft) {}
    func delete(serverIdentity: String) {}
}
