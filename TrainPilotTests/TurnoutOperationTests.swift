import Foundation
import Testing
@testable import TrainPilot

struct TurnoutOperationTests {
    private func turnout(kind: String = "simple", status: String = "known", pending: Bool = false) throws -> Turnout {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "t1", "name": "Entrée", "kind": kind,
            "positions": [
                ["id": "straight", "endpoints": ["main": "position1"]],
                ["id": "diverging", "endpoints": ["main": "position2"]]
            ],
            "desiredPosition": "diverging", "reportedPosition": "straight",
            "pending": pending, "reportedStatus": status, "commandStatus": "idle"
        ])
        return try JSONDecoder().decode(Turnout.self, from: data)
    }

    @Test func clickUsesReportedPositionAndRequiresAnUnambiguousSimpleTurnout() throws {
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout()) == "diverging")
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(kind: "three_way")) == nil)
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(kind: "double_slip")) == nil)
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(status: "unknown")) == nil)
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(status: "invalid")) == nil)
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(pending: true)) == nil)
    }

    @Test func highlightedPathUsesReportedStateAndHidesUnknownPosition() throws {
        let points = [LayoutPoint(x: -10, y: 0), LayoutPoint(x: 0, y: 0), LayoutPoint(x: 10, y: 0)]
        let plan = TopologyRenderPlan.Turnout(
            presentation: LayoutTurnoutPresentation(turnoutId: "t1", x: 0, y: 0, rotationDegrees: 0, mirrored: false),
            ports: points, blockStyles: [], blockIDs: [],
            pathsByPosition: ["straight": [points], "diverging": []]
        )
        #expect(plan.reportedPaths(in: TopologyRuntimeState(turnouts: [try turnout()])) == [points])
        #expect(plan.reportedPaths(in: TopologyRuntimeState(turnouts: [try turnout(status: "unknown")])).isEmpty)
        #expect(plan.reportedPaths(in: .empty).isEmpty)
    }
}
