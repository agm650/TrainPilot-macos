import XCTest
@testable import TrainPilot

final class RuntimeLayoutTests: XCTestCase {
    func testDecodesCurrentRuntimeBlockAndTurnoutContracts() throws {
        let blockData = Data(
            """
            {
              "id": "b1",
              "name": "Gare",
              "occupied": true,
              "occupancy": {
                "state": "occupied",
                "occupant": {"type": "locomotive", "id": "l1"},
                "updatedAt": "2026-09-26T12:00:00Z"
              }
            }
            """.utf8
        )
        let turnoutData = Data(
            """
            {
              "id": "t1",
              "name": "Entrée",
              "kind": "three_way",
              "endpoints": [
                {"id": "A", "linearAddress": 20, "inverted": false},
                {"id": "B", "linearAddress": 21, "inverted": false}
              ],
              "positions": [
                {"id": "left", "label": "Gauche", "endpoints": {"A": "position2", "B": "position1"}},
                {"id": "right", "label": "Droite", "endpoints": {"A": "position1", "B": "position2"}}
              ],
              "desiredPosition": "right",
              "reportedPosition": "left",
              "pending": true,
              "reportedStatus": "known",
              "reportQuality": "station",
              "commandStatus": "pending"
            }
            """.utf8
        )

        let block = try JSONDecoder.trainPilot.decode(Block.self, from: blockData)
        let turnout = try JSONDecoder.trainPilot.decode(Turnout.self, from: turnoutData)

        XCTAssertEqual(block.occupancyState, .occupied)
        XCTAssertEqual(block.occupancy?.occupant?.id, "l1")
        XCTAssertEqual(turnout.positions.map(\.id), ["left", "right"])
        XCTAssertEqual(turnout.desiredPosition, "right")
        XCTAssertEqual(turnout.reportedPosition, "left")
    }

    func testRuntimeVisualStatesPrioritizeOccupancyAndConfirmation() throws {
        let block = try JSONDecoder.trainPilot.decode(
            Block.self,
            from: Data(
                """
                {
                  "id": "b1",
                  "name": "Gare",
                  "occupied": true,
                  "occupancy": {
                    "state": "occupied",
                    "updatedAt": "2026-09-26T12:00:00Z"
                  }
                }
                """.utf8
            )
        )
        let turnout = try decodeTurnout(
            desired: "diverging",
            reported: "straight",
            pending: true,
            status: "known",
            commandStatus: "pending"
        )
        let runtime = TopologyRuntimeState(
            blocks: [block],
            turnouts: [turnout]
        )

        XCTAssertEqual(
            runtime.occupancyEmphasis(for: ["b1"]),
            .occupied
        )
        XCTAssertEqual(
            runtime.turnoutVisualState(for: "t1"),
            .transitioning
        )
        XCTAssertEqual(
            runtime.turnoutVisualState(for: "missing"),
            .unknown
        )
    }

    func testConfirmedAndInconsistentTurnoutStatesAreDistinct() throws {
        let confirmed = try decodeTurnout(
            desired: "straight",
            reported: "straight",
            pending: false,
            status: "known",
            commandStatus: "succeeded"
        )
        let inconsistent = try decodeTurnout(
            desired: "diverging",
            reported: "straight",
            pending: false,
            status: "known",
            commandStatus: "idle"
        )

        XCTAssertEqual(
            TopologyRuntimeState(turnouts: [confirmed])
                .turnoutVisualState(for: "t1"),
            .confirmed
        )
        XCTAssertEqual(
            TopologyRuntimeState(turnouts: [inconsistent])
                .turnoutVisualState(for: "t1"),
            .inconsistent
        )
    }

    func testRenderPlanKeepsBlockMembershipForRuntimeOverlay() {
        let topology = TopologyDefinition(
            revision: "topology",
            nodes: [
                TopologyNode(id: "a", name: nil, kind: .joint),
                TopologyNode(id: "b", name: nil, kind: .joint)
            ],
            trackSections: [
                TrackSection(
                    id: "track",
                    name: "Track",
                    nodeAId: "a",
                    nodeBId: "b",
                    lengthMm: nil
                )
            ],
            turnoutTopologies: [],
            blocks: [
                BlockDefinition(
                    id: "block",
                    name: "Block",
                    trackSectionIds: ["track"],
                    turnoutIds: nil
                )
            ]
        )
        let presentation = LayoutPresentationDefinition(
            revision: "presentation",
            coordinateSystem: "layout-units",
            gridSpacing: 20,
            nodes: [
                LayoutNodePosition(nodeId: "a", x: 0, y: 0),
                LayoutNodePosition(nodeId: "b", x: 100, y: 0)
            ],
            trackSections: [
                LayoutTrackPath(
                    trackSectionId: "track",
                    segments: [.line(to: LayoutPoint(x: 100, y: 0))]
                )
            ],
            turnouts: [],
            blocks: [
                LayoutBlockStyle(blockId: "block", color: "#00FF00", opacity: 0.4)
            ]
        )

        let plan = TopologyRenderPlan(
            topology: topology,
            presentation: presentation
        )

        XCTAssertEqual(plan.tracks.first?.blockIDs, ["block"])
        XCTAssertEqual(TopologyRendererMode.readOnly, .readOnly)
    }

    private func decodeTurnout(
        desired: String,
        reported: String,
        pending: Bool,
        status: String,
        commandStatus: String
    ) throws -> Turnout {
        let json = """
        {
          "id": "t1",
          "name": "Entrée",
          "kind": "simple",
          "endpoints": [{"id": "main", "linearAddress": 1, "inverted": false}],
          "positions": [
            {"id": "straight", "endpoints": {"main": "position1"}},
            {"id": "diverging", "endpoints": {"main": "position2"}}
          ],
          "desiredPosition": "\(desired)",
          "reportedPosition": "\(reported)",
          "pending": \(pending),
          "reportedStatus": "\(status)",
          "commandStatus": "\(commandStatus)"
        }
        """
        return try JSONDecoder.trainPilot.decode(
            Turnout.self,
            from: Data(json.utf8)
        )
    }
}
