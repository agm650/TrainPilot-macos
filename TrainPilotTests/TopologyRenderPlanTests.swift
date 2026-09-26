import XCTest
@testable import TrainPilot

final class TopologyRenderPlanTests: XCTestCase {
    func testEmptyCanvasProducesEmptyPlan() {
        let plan = TopologyRenderPlan(
            topology: TopologyDefinition(
                revision: "t",
                nodes: [], trackSections: [], turnoutTopologies: [], blocks: []
            ),
            presentation: LayoutPresentationDefinition(
                revision: "p", coordinateSystem: "layout-units", gridSpacing: 20,
                nodes: [], trackSections: [], turnouts: [], blocks: []
            )
        )

        XCTAssertTrue(plan.tracks.isEmpty)
        XCTAssertTrue(plan.turnouts.isEmpty)
    }

    func testPlanKeepsCurvesTurnoutsAndBlockOverlays() {
        let topology = TopologyDefinition(
            revision: "t",
            nodes: [TopologyNode(id: "n1", name: nil, kind: .joint)],
            trackSections: [
                TrackSection(
                    id: "s1", name: "Section", nodeAId: "n1",
                    nodeBId: "n2", lengthMm: nil
                )
            ],
            turnoutTopologies: [],
            blocks: [
                BlockDefinition(
                    id: "b1", name: "Block", trackSectionIds: ["s1"],
                    turnoutIds: nil
                )
            ]
        )
        let presentation = LayoutPresentationDefinition(
            revision: "p", coordinateSystem: "layout-units", gridSpacing: 20,
            nodes: [LayoutNodePosition(nodeId: "n1", x: -500, y: 900)],
            trackSections: [
                LayoutTrackPath(
                    trackSectionId: "s1",
                    segments: [
                        .cubic(
                            control1: LayoutPoint(x: 10, y: 20),
                            control2: LayoutPoint(x: 30, y: 40),
                            to: LayoutPoint(x: 50, y: 60)
                        )
                    ]
                )
            ],
            turnouts: [
                LayoutTurnoutPresentation(
                    turnoutId: "t1", x: 80, y: 60,
                    rotationDegrees: 90, mirrored: false
                )
            ],
            blocks: [LayoutBlockStyle(blockId: "b1", color: "#FF0000", opacity: 0.4)]
        )

        let plan = TopologyRenderPlan(topology: topology, presentation: presentation)

        XCTAssertEqual(plan.tracks.count, 1)
        XCTAssertEqual(plan.tracks[0].start, LayoutPoint(x: -500, y: 900))
        XCTAssertEqual(plan.tracks[0].blockStyles.count, 1)
        XCTAssertEqual(plan.turnouts.count, 1)
    }
}
