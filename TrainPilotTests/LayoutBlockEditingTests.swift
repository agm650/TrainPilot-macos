import XCTest
@testable import TrainPilot

@MainActor
final class LayoutBlockEditingTests: XCTestCase {
    func testCreatesBlockAndClampsOpacity() {
        let controller = makeController()
        controller.addBlock(id: "b1", name: "Gare", color: "#12ABEF", opacity: 2)

        XCTAssertEqual(controller.document.topology.blocks[0].name, "Gare")
        XCTAssertEqual(controller.document.presentation.blocks[0].color, "#12ABEF")
        XCTAssertEqual(controller.document.presentation.blocks[0].opacity, 1)
    }

    func testAddsAndRemovesTrackAndTurnoutMembers() throws {
        let controller = makeController()
        controller.addBlock(id: "b1")

        try controller.add(.trackSection("s1"), toBlock: "b1")
        try controller.add(.turnout("t1"), toBlock: "b1")
        XCTAssertEqual(controller.document.topology.blocks[0].trackSectionIds, ["s1"])
        XCTAssertEqual(controller.document.topology.blocks[0].turnoutIds, ["t1"])

        try controller.remove(.trackSection("s1"), fromBlock: "b1")
        XCTAssertTrue(controller.document.topology.blocks[0].trackSectionIds.isEmpty)
    }

    func testStyleChangeAndMembershipSupportUndoRedo() throws {
        let controller = makeController()
        controller.addBlock(id: "b1")
        try controller.updateBlockStyle(blockID: "b1", color: "#FF0000", opacity: 0.7)
        controller.undo()
        XCTAssertEqual(controller.document.presentation.blocks[0].color, "#33AADD")
        controller.redo()
        XCTAssertEqual(controller.document.presentation.blocks[0].color, "#FF0000")
    }

    func testDeletingBlockDoesNotDeleteRailResources() throws {
        let controller = makeController()
        controller.addBlock(id: "b1")
        try controller.add(.trackSection("s1"), toBlock: "b1")
        controller.select(.block("b1"))
        try controller.deleteSelection()

        XCTAssertTrue(controller.document.topology.blocks.isEmpty)
        XCTAssertEqual(controller.document.topology.trackSections.count, 1)
        XCTAssertEqual(controller.document.topology.turnoutTopologies.count, 1)
    }

    func testValidatorDetectsInvalidStyleAndUnknownMember() {
        let controller = makeController()
        let topology = controller.document.topology.replacing(
            blocks: [
                BlockDefinition(
                    id: "b1", name: "Block", trackSectionIds: ["missing"],
                    turnoutIds: []
                )
            ]
        )
        let presentation = controller.document.presentation.replacing(
            blocks: [LayoutBlockStyle(blockId: "b1", color: "red", opacity: 2)]
        )

        let issues = LayoutBlockValidator().validate(
            topology: topology,
            presentation: presentation
        )
        XCTAssertTrue(issues.contains(.invalidColor(blockID: "b1", color: "red")))
        XCTAssertTrue(issues.contains(.invalidOpacity(blockID: "b1", opacity: 2)))
        XCTAssertTrue(
            issues.contains(.unknownTrackSection(blockID: "b1", sectionID: "missing"))
        )
    }

    func testRenderPlanKeepsDistinctBlockStyles() throws {
        let controller = makeController()
        controller.addBlock(id: "b1", color: "#FF0000", opacity: 0.4)
        controller.addBlock(id: "b2", color: "#0000FF", opacity: 0.6)
        try controller.add(.trackSection("s1"), toBlock: "b1")
        try controller.add(.trackSection("s1"), toBlock: "b2")

        let plan = TopologyRenderPlan(
            topology: controller.document.topology,
            presentation: controller.document.presentation
        )
        XCTAssertEqual(plan.tracks[0].blockStyles.map(\.blockId), ["b1", "b2"])
    }

    private func makeController() -> LayoutEditorController {
        let snapshot = LayoutSnapshot(
            topology: TopologyDefinition(
                revision: "t",
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
                blocks: []
            ),
            presentation: LayoutPresentationDefinition(
                revision: "p", coordinateSystem: "layout-units", gridSpacing: 20,
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
                        turnoutId: "t1", x: 50, y: 20,
                        rotationDegrees: 0, mirrored: false
                    )
                ],
                blocks: []
            )
        )
        return LayoutEditorController(
            document: LayoutEditorDocument(
                serverIdentity: "server", snapshot: snapshot,
                draftStore: LayoutDraftStoreSpyForBlockEditing(),
                autosaveDelayNanoseconds: 10_000_000_000
            )
        )
    }
}

private actor LayoutDraftStoreSpyForBlockEditing: LayoutDraftStoring {
    func load(serverIdentity: String) -> LayoutDraft? { nil }
    func save(_ draft: LayoutDraft) {}
    func delete(serverIdentity: String) {}
}
