import Foundation
import Testing
@testable import TrainPilot

@MainActor
struct LayoutTileEditingTests {
    @Test func adjacentTracksShareOneJointAndUndoIsAtomic() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.straight)
        try controller.placeTile(at: LayoutPoint(x: 3, y: 7))
        try controller.placeTile(at: LayoutPoint(x: 23, y: 7))
        let sections = controller.document.topology.trackSections
        #expect(sections.count == 2)
        #expect(sections[0].nodeBId == sections[1].nodeAId)
        #expect(controller.document.topology.nodes.count == 3)
        controller.undo()
        #expect(controller.document.topology.trackSections.count == 1)
        #expect(controller.document.topology.nodes.count == 2)
        controller.redo()
        #expect(controller.document.topology.trackSections == sections)
    }

    @Test func deletingLineRemovesOnlyUnusedConnectionsAndSupportsUndo() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        for x in [1.0, 21, 41] {
            try controller.placeTile(at: LayoutPoint(x: x, y: 1))
        }
        let originalTopology = controller.document.topology
        let originalPresentation = controller.document.presentation
        let sections = originalTopology.trackSections
        controller.select(.trackSection(sections[1].id))
        try controller.deleteSelection()
        // Both ends of the middle section are still used by its neighbors.
        #expect(controller.document.topology.nodes.count == 4)
        controller.select(.trackSection(sections[0].id))
        try controller.deleteSelection()
        #expect(controller.document.topology.nodes.count == 2)
        #expect(controller.document.presentation.nodes.count == 2)
        controller.select(.trackSection(sections[2].id))
        try controller.deleteSelection()
        #expect(controller.document.topology.nodes.isEmpty)
        #expect(controller.document.presentation.nodes.isEmpty)
        controller.undo()
        controller.undo()
        controller.undo()
        #expect(controller.document.topology == originalTopology)
        #expect(controller.document.presentation == originalPresentation)
        controller.redo()
        controller.redo()
        controller.redo()
        #expect(controller.document.presentation.nodes.isEmpty)
    }

    @Test(arguments: [true, false])
    func deletionPreservesConnectionsUsedByTracksOrTurnouts(deleteTrackFirst: Bool) throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.rightTurnout)
        try controller.placeTile(at: LayoutPoint(x: 21, y: 1))
        let turnout = try #require(controller.document.topology.turnoutTopologies.first)
        controller.selectTile(.straight)
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        let track = try #require(controller.document.topology.trackSections.first)
        controller.select(deleteTrackFirst ? .trackSection(track.id) : .turnout(turnout.turnoutId))
        try controller.deleteSelection()
        #expect(controller.document.topology.nodes.contains { $0.id == track.nodeBId })
        #expect(controller.document.topology.nodes.count == (deleteTrackFirst ? 3 : 2))
        #expect(controller.document.presentation.nodes.count == (deleteTrackFirst ? 3 : 2))
        controller.select(deleteTrackFirst ? .turnout(turnout.turnoutId) : .trackSection(track.id))
        try controller.deleteSelection()
        #expect(controller.document.topology.nodes.isEmpty)
        #expect(controller.document.presentation.nodes.isEmpty)
    }

    @Test func cellCenterSelectsTrackForDeletionAndReplacement() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        let track = try #require(controller.document.topology.trackSections.first)
        controller.selectElement(at: LayoutPoint(x: 10, y: 10), tolerance: 10)
        #expect(controller.selection == .trackSection(track.id))
        try controller.deleteSelection()
        controller.selectTile(.curve)
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        #expect(controller.document.topology.trackSections.count == 1)
    }

    @Test func occupiedCellRejectsPlacementWithoutMutation() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        let before = controller.document.topology
        controller.selectTile(.curve)
        #expect(throws: LayoutTileError.self) {
            try controller.placeTile(at: LayoutPoint(x: 19, y: 19))
        }
        #expect(controller.document.topology == before)
    }

    @Test func negativeCoordinatesUseContainingCell() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        try controller.placeTile(at: LayoutPoint(x: -1, y: -1))
        let positions = controller.document.presentation.nodes
        #expect(positions[0].x == -20)
        #expect(positions[0].y == -10)
        #expect(positions[1].x == 0)
    }

    @Test(arguments: LayoutTileProfile.allCases)
    func profilesFitOneCellAtEveryRotation(_ profile: LayoutTileProfile) throws {
        for rotation in 0..<8 {
            let controller = LayoutStudioSession(canPublish: false).controller
            controller.selectTile(profile)
            controller.tileRotationSteps = rotation
            try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
            #expect(controller.document.presentation.nodes.allSatisfy {
                (0...20).contains($0.x) && (0...20).contains($0.y)
            })
            #expect(LayoutTrackValidator().validate(
                topology: controller.document.topology,
                presentation: controller.document.presentation
            ).isEmpty)
            controller.undo()
            #expect(controller.document.topology.nodes.isEmpty)
            #expect(controller.document.turnoutDefinitions.isEmpty)
        }
    }

    @Test(arguments: [LayoutTileProfile.leftTurnout, .rightTurnout, .threeWay])
    func turnoutBranchesAreAt45Degrees(_ profile: LayoutTileProfile) throws {
        for rotation in 0..<8 {
            let controller = LayoutStudioSession(canPublish: false).controller
            controller.selectTile(profile)
            controller.tileRotationSteps = rotation
            try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
            let turnout = try #require(controller.document.presentation.turnouts.first)
            let nodes = controller.document.presentation.nodes
            let straight = nodes[profile == .threeWay ? 2 : 1]
            let branches = profile == .threeWay ? [nodes[1], nodes[3]] : [nodes[2]]
            let axisX = straight.x - turnout.x
            let axisY = straight.y - turnout.y
            for branch in branches {
                let branchX = branch.x - turnout.x
                let branchY = branch.y - turnout.y
                let dot = axisX * branchX + axisY * branchY
                let cross = axisX * branchY - axisY * branchX
                #expect(dot > 0)
                #expect(abs(dot - abs(cross)) < 0.000001)
            }
        }
    }

    @Test func diagonalConnectsTo45DegreeTurnoutBranch() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.leftTurnout)
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        controller.selectTile(.straight)
        controller.tileRotationSteps = 7
        try controller.placeTile(at: LayoutPoint(x: 21, y: -1))
        let turnout = try #require(controller.document.topology.turnoutTopologies.first)
        let track = try #require(controller.document.topology.trackSections.first)
        #expect(turnout.ports[2].nodeId == track.nodeAId)
    }

    @Test func rotatedCurveConnectsTwoDiagonalRailsWithContinuousTangents() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.curve)
        controller.tileRotationSteps = 1
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        let curve = try #require(controller.document.topology.trackSections.first)
        let path = try #require(controller.document.presentation.trackSections.first)
        controller.selectTile(.straight)
        try controller.placeTile(at: LayoutPoint(x: -19, y: -19))
        controller.tileRotationSteps = 7
        try controller.placeTile(at: LayoutPoint(x: 21, y: -19))
        let sections = controller.document.topology.trackSections
        #expect(sections[1].nodeBId == curve.nodeAId)
        #expect(sections[2].nodeAId == curve.nodeBId)
        guard case .cubic(let control1, let control2, let end) = path.segments[0] else {
            Issue.record("Expected a curved rail")
            return
        }
        #expect(control1.x > 0 && control1.x == control1.y)
        #expect(control2.x < 20 && abs((end.x - control2.x) - control2.y) < 0.000001)
        #expect(end == LayoutPoint(x: 20, y: 0))
    }

    @Test(arguments: LayoutTileProfile.allCases)
    func rotationKeepsPortsOnGridAndWrapsAfterEightSteps(_ profile: LayoutTileProfile) {
        for port in profile.ports {
            #expect(profile.point(port, rotationSteps: 8) == port)
            #expect(profile.point(port, rotationSteps: -1) == profile.point(port, rotationSteps: 7))
            for step in 0..<8 {
                let rotated = profile.point(port, rotationSteps: step)
                #expect([0.0, 0.5, 1.0].contains(rotated.x))
                #expect([0.0, 0.5, 1.0].contains(rotated.y))
                #expect(rotated.x == 0 || rotated.x == 1 || rotated.y == 0 || rotated.y == 1)
            }
        }
    }

    @Test func curveConnectsAtEdgeMidpoints() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.curve)
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        controller.selectTile(.straight)
        controller.tileRotationSteps = 2
        try controller.placeTile(at: LayoutPoint(x: 1, y: -1))
        let sections = controller.document.topology.trackSections
        #expect(sections[0].nodeBId == sections[1].nodeBId)
    }

    @Test func turnoutSharesJointAndCannotBreakConnectedTrackByRotation() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.rightTurnout)
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        controller.selectTile(.straight)
        try controller.placeTile(at: LayoutPoint(x: -1, y: 1))
        let turnout = try #require(controller.document.topology.turnoutTopologies.first)
        let track = try #require(controller.document.topology.trackSections.first)
        #expect(turnout.ports[0].nodeId == track.nodeBId)
        let before = controller.document.presentation
        #expect(throws: LayoutTileError.self) {
            try controller.transformTurnout(id: turnout.turnoutId, rotationDegrees: 90)
        }
        #expect(controller.document.presentation == before)
    }

    @Test func archiveRoundTripPreservesTilesAndConnections() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.doubleSlip)
        controller.tileRotationSteps = 1
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        let service = LayoutStudioArchiveService()
        let archive = try service.archive(for: controller.document, filename: "tiles.dcclayout")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try archive.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = try service.read(from: url)
        #expect(contents.snapshot.topology.nodes == controller.document.topology.nodes)
        #expect(contents.snapshot.presentation.turnouts == controller.document.presentation.turnouts)
        #expect(contents.turnouts == controller.document.turnoutDefinitions)
    }
}
