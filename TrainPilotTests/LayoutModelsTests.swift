import XCTest
@testable import TrainPilot

final class LayoutModelsTests: XCTestCase {
    func testDecodesEmptyTopology() throws {
        let topology = try decode(
            TopologyDefinition.self,
            """
            {
              "revision": "topology-1",
              "nodes": [],
              "trackSections": [],
              "turnoutTopologies": [],
              "blocks": []
            }
            """
        )

        XCTAssertEqual(topology.revision, "topology-1")
        XCTAssertTrue(topology.nodes.isEmpty)
        XCTAssertTrue(topology.trackSections.isEmpty)
        XCTAssertTrue(topology.turnoutTopologies.isEmpty)
        XCTAssertTrue(topology.blocks.isEmpty)
    }

    func testDecodesTopologyResources() throws {
        let topology = try decode(
            TopologyDefinition.self,
            """
            {
              "revision": "topology-1",
              "nodes": [
                { "id": "N1", "name": "Entrée", "kind": "boundary" },
                { "id": "N2", "kind": "joint" }
              ],
              "trackSections": [
                {
                  "id": "S1", "name": "Voie 1", "nodeAId": "N1",
                  "nodeBId": "N2", "lengthMm": 1200
                }
              ],
              "turnoutTopologies": [
                {
                  "turnoutId": "T1",
                  "ports": [
                    { "id": "toe", "nodeId": "N2" },
                    { "id": "straight", "nodeId": "N3" }
                  ],
                  "positions": [
                    {
                      "positionId": "straight",
                      "connections": [
                        { "portAId": "toe", "portBId": "straight" }
                      ]
                    }
                  ]
                }
              ],
              "blocks": [
                {
                  "id": "B1", "name": "Quai",
                  "trackSectionIds": ["S1"], "turnoutIds": ["T1"]
                }
              ]
            }
            """
        )

        XCTAssertEqual(topology.nodes[0].kind, .boundary)
        XCTAssertEqual(topology.trackSections[0].lengthMm, 1200)
        XCTAssertEqual(topology.turnoutTopologies[0].ports.count, 2)
        XCTAssertEqual(
            topology.turnoutTopologies[0].positions[0].connections[0].portBId,
            "straight"
        )
        XCTAssertEqual(topology.blocks[0].turnoutIds, ["T1"])
    }

    func testDecodesEmptyPresentation() throws {
        let presentation = try decode(
            LayoutPresentationDefinition.self,
            """
            {
              "revision": "presentation-1",
              "coordinateSystem": "layout-units",
              "gridSpacing": 20,
              "nodes": [], "trackSections": [], "turnouts": [], "blocks": []
            }
            """
        )

        XCTAssertEqual(presentation.coordinateSystem, "layout-units")
        XCTAssertEqual(presentation.gridSpacing, 20)
        XCTAssertTrue(presentation.nodes.isEmpty)
    }

    func testDecodesLineAndCubicSegments() throws {
        let presentation = try decode(
            LayoutPresentationDefinition.self,
            """
            {
              "revision": "presentation-1",
              "coordinateSystem": "layout-units",
              "gridSpacing": 10,
              "nodes": [{ "nodeId": "N1", "x": 5.5, "y": 10 }],
              "trackSections": [{
                "trackSectionId": "S1",
                "segments": [
                  { "type": "line", "to": { "x": 20, "y": 10 } },
                  {
                    "type": "cubic",
                    "control1": { "x": 25, "y": 10 },
                    "control2": { "x": 30, "y": 20 },
                    "to": { "x": 40, "y": 20 }
                  }
                ]
              }],
              "turnouts": [], "blocks": []
            }
            """
        )

        XCTAssertEqual(
            presentation.trackSections[0].segments,
            [
                .line(to: LayoutPoint(x: 20, y: 10)),
                .cubic(
                    control1: LayoutPoint(x: 25, y: 10),
                    control2: LayoutPoint(x: 30, y: 20),
                    to: LayoutPoint(x: 40, y: 20)
                )
            ]
        )
    }

    func testDecodesTurnoutPlacementAndBlockStyle() throws {
        let presentation = try decode(
            LayoutPresentationDefinition.self,
            """
            {
              "revision": "presentation-1",
              "coordinateSystem": "layout-units",
              "gridSpacing": 20,
              "nodes": [], "trackSections": [],
              "turnouts": [{
                "turnoutId": "T1", "x": 100, "y": 50,
                "rotationDegrees": 45, "mirrored": true
              }],
              "blocks": [{ "blockId": "B1", "color": "#12ABEF", "opacity": 0.4 }]
            }
            """
        )

        XCTAssertEqual(presentation.turnouts[0].rotationDegrees, 45)
        XCTAssertTrue(presentation.turnouts[0].mirrored)
        XCTAssertEqual(presentation.blocks[0].color, "#12ABEF")
        XCTAssertEqual(presentation.blocks[0].opacity, 0.4)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.trainPilot.decode(T.self, from: Data(json.utf8))
    }
}
