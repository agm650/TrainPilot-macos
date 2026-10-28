import CoreGraphics
import Testing
@testable import TrainPilot

@MainActor
struct LayoutSelectionEditingTests {
    @Test func defaultCanvasScaleIsFormer175PercentAndPanPreservesCoordinates() {
        let transform = LayoutViewportTransform(zoom: LayoutViewportTransform.canvasBaseZoom)
        let point = LayoutPoint(x: 20, y: 40)
        #expect(transform.canvasPoint(for: point) == CGPoint(x: 35, y: 70))
        let panned = transform.pannedBy(x: 100, y: -50)
        #expect(panned.canvasPoint(for: point) == CGPoint(x: 135, y: 20))
        #expect(panned.layoutPoint(for: CGPoint(x: 135, y: 20)) == point)
        let anchor = CGPoint(x: 250, y: 150)
        let zoomed = panned.zoomed(to: 3, around: anchor)
        let reset = zoomed.zoomed(to: LayoutViewportTransform.canvasBaseZoom, around: anchor)
        #expect(abs(reset.panX - panned.panX) < 0.000001)
        #expect(abs(reset.panY - panned.panY) < 0.000001)
    }

    @Test func rectangleSelectsWholePiecesInEitherDirection() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        for x in [1.0, 21, 81] {
            try controller.placeTile(at: LayoutPoint(x: x, y: 1))
        }
        let sections = controller.document.topology.trackSections
        let expected: Set<LayoutEditorSelection> = [.trackSection(sections[0].id), .trackSection(sections[1].id)]
        let start = LayoutPoint(x: -1, y: -1)
        let end = LayoutPoint(x: 41, y: 21)
        #expect(controller.elements(inRectangleFrom: start, to: end) == expected)
        #expect(controller.elements(inRectangleFrom: end, to: start) == expected)
    }

    @Test func movingAdjacentTracksSnapsOnceAndUndoRestoresAllGeometry() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        for x in [1.0, 21] { try controller.placeTile(at: LayoutPoint(x: x, y: 1)) }
        let topology = controller.document.topology
        let presentation = controller.document.presentation
        controller.selectElements(Set(topology.trackSections.map { .trackSection($0.id) }))
        controller.beginDrag()
        controller.updateSelectionDrag(delta: LayoutPoint(x: 19, y: 41), snapEnabled: true)
        controller.updateSelectionDrag(delta: LayoutPoint(x: 39, y: 61), snapEnabled: true)
        controller.endDrag()
        #expect(controller.document.topology == topology)
        for (before, after) in zip(presentation.nodes, controller.document.presentation.nodes) {
            #expect(after.x == before.x + 40)
            #expect(after.y == before.y + 60)
        }
        let moved = controller.document.presentation
        controller.undo()
        #expect(controller.document.presentation == presentation)
        controller.redo()
        #expect(controller.document.presentation == moved)
    }

    @Test func movingPartialLineDetachesSharedNodeWithoutStretchingNeighbor() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        for x in [1.0, 21] { try controller.placeTile(at: LayoutPoint(x: x, y: 1)) }
        let original = controller.document.topology
        let presentation = controller.document.presentation
        controller.select(.trackSection(original.trackSections[0].id))
        controller.beginDrag()
        controller.updateSelectionDrag(delta: LayoutPoint(x: 0, y: 20), snapEnabled: true)
        controller.endDrag()
        let moved = controller.document.topology.trackSections[0]
        let stationary = controller.document.topology.trackSections[1]
        #expect(stationary == original.trackSections[1])
        #expect(moved.nodeBId != stationary.nodeAId)
        #expect(controller.document.presentation.nodes.first { $0.nodeId == stationary.nodeAId } ==
            presentation.nodes.first { $0.nodeId == stationary.nodeAId })
        #expect(controller.document.presentation.trackSections[1] == presentation.trackSections[1])
        #expect(LayoutTrackValidator().validate(
            topology: controller.document.topology, presentation: controller.document.presentation
        ).isEmpty)
        controller.undo()
        #expect(controller.document.topology == original)
        #expect(controller.document.presentation == presentation)
    }

    @Test func movingCurveAndTurnoutPreservesControlPointsAndDCCMapping() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        controller.selectTile(.curve)
        controller.tileRotationSteps = 1
        try controller.placeTile(at: LayoutPoint(x: 1, y: 1))
        controller.selectTile(.leftTurnout)
        try controller.placeTile(at: LayoutPoint(x: 61, y: 1))
        let before = controller.document.presentation
        let definitions = controller.document.turnoutDefinitions
        let selections: Set<LayoutEditorSelection> = [
            .trackSection(controller.document.topology.trackSections[0].id),
            .turnout(definitions[0].id)
        ]
        controller.selectElements(selections)
        controller.beginDrag()
        controller.updateSelectionDrag(delta: LayoutPoint(x: -20, y: 40), snapEnabled: true)
        let after = controller.document.presentation
        if case .cubic(let a, let b, let end) = before.trackSections[0].segments[0],
           case .cubic(let movedA, let movedB, let movedEnd) = after.trackSections[0].segments[0] {
            #expect(movedA == LayoutPoint(x: a.x - 20, y: a.y + 40))
            #expect(movedB == LayoutPoint(x: b.x - 20, y: b.y + 40))
            #expect(movedEnd == LayoutPoint(x: end.x - 20, y: end.y + 40))
        } else {
            Issue.record("The curve must remain cubic")
        }
        #expect(after.turnouts[0].x == before.turnouts[0].x - 20)
        #expect(after.turnouts[0].y == before.turnouts[0].y + 40)
        #expect(controller.document.turnoutDefinitions == definitions)
        controller.cancelDrag()
        #expect(controller.document.presentation == before)
    }

    @Test func ReturningDragToOriginRestoresSharedNodes() throws {
        let controller = LayoutStudioSession(canPublish: false).controller
        for x in [1.0, 21] { try controller.placeTile(at: LayoutPoint(x: x, y: 1)) }
        let topology = controller.document.topology
        let presentation = controller.document.presentation
        controller.select(.trackSection(topology.trackSections[0].id))
        controller.beginDrag()
        controller.updateSelectionDrag(delta: LayoutPoint(x: 5, y: 7), snapEnabled: false)
        controller.updateSelectionDrag(delta: LayoutPoint(x: 0, y: 0), snapEnabled: false)
        controller.endDrag()
        #expect(controller.document.topology == topology)
        #expect(controller.document.presentation == presentation)
    }
}
