import Foundation
import Testing
@testable import TrainPilot

struct TurnoutOperationTests {
    private func turnout(
        kind: String = "simple", status: String = "known", pending: Bool = false,
        positions: [String] = ["straight", "diverging"],
        reportedPosition: String = "straight", commandStatus: String = "idle"
    ) throws -> Turnout {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "t1", "name": "Entrée", "kind": kind,
            "positions": positions.map { ["id": $0, "endpoints": ["main": "position1"]] },
            "desiredPosition": "diverging", "reportedPosition": reportedPosition,
            "pending": pending, "reportedStatus": status, "commandStatus": commandStatus
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

    @Test func tripleClickCyclesThroughAllReportedPositions() throws {
        let positions = ["straight", "left", "right"]
        for (current, expected) in [("straight", "left"), ("left", "right"), ("right", "straight")] {
            let value = try turnout(kind: "three_way", positions: positions, reportedPosition: current)
            #expect(TopologyRuntimeState.toggleTarget(for: value) == expected)
        }
    }

    @Test func tripleClickRequiresKnownPositionAndNoPendingOrFailedCommand() throws {
        let positions = ["straight", "left", "right"]
        for status in ["unknown", "invalid"] {
            #expect(TopologyRuntimeState.toggleTarget(for: try turnout(
                kind: "three_way", status: status, positions: positions
            )) == nil)
        }
        for command in ["pending", "failed", "timeout"] {
            #expect(TopologyRuntimeState.toggleTarget(for: try turnout(
                kind: "three_way", positions: positions, commandStatus: command
            )) == nil)
        }
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(
            kind: "three_way", pending: true, positions: positions
        )) == nil)
        #expect(TopologyRuntimeState.toggleTarget(for: try turnout(
            kind: "three_way", positions: positions, reportedPosition: "missing"
        )) == nil)
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
