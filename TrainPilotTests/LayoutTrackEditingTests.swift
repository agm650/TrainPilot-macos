import XCTest
@testable import TrainPilot

@MainActor
final class LayoutTrackEditingTests: XCTestCase {
    func testCreatesStraightAndMultiSegmentTracksWithSnap() {
        let controller = makeEmptyController()
        let id = controller.addTrackSection(
            id: "s1",
            start: LayoutPoint(x: 3, y: 4),
            intermediatePoints: [LayoutPoint(x: 43, y: 17)],
            end: LayoutPoint(x: 97, y: 42),
            transform: LayoutViewportTransform(zoom: 2),
            snapEnabled: true,
            optionKeyPressed: false
        )

        XCTAssertEqual(id, "s1")
        XCTAssertEqual(controller.document.topology.nodes.count, 2)
        XCTAssertEqual(controller.document.presentation.trackSections[0].segments.count, 2)
        XCTAssertEqual(
            controller.document.presentation.trackSections[0].segments.last?.endPoint,
            LayoutPoint(x: 100, y: 40)
        )
        XCTAssertEqual(controller.selection, .trackSection("s1"))
    }

    func testConnectsToExistingNodeAtDifferentZoom() {
        let controller = makeEmptyController()
        _ = controller.addTrackSection(
            id: "s1", start: LayoutPoint(x: 0, y: 0),
            end: LayoutPoint(x: 100, y: 0),
            transform: LayoutViewportTransform(), snapEnabled: false,
            optionKeyPressed: false
        )
        _ = controller.addTrackSection(
            id: "s2", start: LayoutPoint(x: 102, y: 1),
            end: LayoutPoint(x: 200, y: 0),
            transform: LayoutViewportTransform(zoom: 2), snapEnabled: false,
            optionKeyPressed: false, connectionToleranceCanvas: 10
        )

        let sections = controller.document.topology.trackSections
        XCTAssertEqual(sections[0].nodeBId, sections[1].nodeAId)
        XCTAssertEqual(controller.document.topology.nodes.count, 3)
    }

    func testConvertsLineToBezierAndBack() throws {
        let controller = makeControllerWithTrack()
        try controller.convertTrackSegmentToCubic(sectionID: "s1", segmentIndex: 0)

        guard case .cubic = controller.document.presentation
            .trackSections[0].segments[0] else {
            return XCTFail("Expected cubic segment")
        }
        try controller.convertTrackSegmentToLine(sectionID: "s1", segmentIndex: 0)
        XCTAssertEqual(
            controller.document.presentation.trackSections[0].segments[0],
            .line(to: LayoutPoint(x: 100, y: 0))
        )
    }

    func testMovesBezierControlWithAndWithoutSnap() throws {
        let controller = makeControllerWithTrack()
        try controller.convertTrackSegmentToCubic(sectionID: "s1", segmentIndex: 0)
        try controller.moveBezierControl(
            sectionID: "s1", segmentIndex: 0, controlIndex: 1,
            to: LayoutPoint(x: 23, y: 17),
            transform: LayoutViewportTransform(zoom: 3),
            snapEnabled: true, optionKeyPressed: false
        )

        guard case .cubic(let control1, _, _) = controller.document.presentation
            .trackSections[0].segments[0] else {
            return XCTFail("Expected cubic segment")
        }
        XCTAssertEqual(control1, LayoutPoint(x: 20, y: 20))
    }

    func testCreationUndoRedo() {
        let controller = makeEmptyController()
        _ = controller.addTrackSection(
            id: "s1", start: LayoutPoint(x: 0, y: 0),
            end: LayoutPoint(x: 100, y: 0),
            transform: LayoutViewportTransform(), snapEnabled: false,
            optionKeyPressed: false
        )
        controller.undo()
        XCTAssertTrue(controller.document.topology.trackSections.isEmpty)
        controller.redo()
        XCTAssertEqual(controller.document.topology.trackSections.count, 1)
    }

    func testLocalValidationDetectsEndpointMismatch() {
        let controller = makeControllerWithTrack()
        let invalidPresentation = controller.document.presentation.replacing(
            trackSections: [
                LayoutTrackPath(
                    trackSectionId: "s1",
                    segments: [.line(to: LayoutPoint(x: 90, y: 0))]
                )
            ]
        )

        let issues = LayoutTrackValidator().validate(
            topology: controller.document.topology,
            presentation: invalidPresentation
        )
        XCTAssertTrue(issues.contains(.endpointMismatch("s1")))
    }

    func testGraphicalLengthDoesNotInventPhysicalLength() {
        let controller = makeControllerWithTrack()
        let length = controller.graphicalLength(of: "s1")
        XCTAssertNotNil(length)
        XCTAssertEqual(length ?? 0, 100, accuracy: 0.001)
        XCTAssertNil(controller.document.topology.trackSections[0].lengthMm)
    }

    private func makeEmptyController() -> LayoutEditorController {
        makeController(snapshot: makeEditorSnapshot())
    }

    private func makeControllerWithTrack() -> LayoutEditorController {
        let controller = makeEmptyController()
        _ = controller.addTrackSection(
            id: "s1", start: LayoutPoint(x: 0, y: 0),
            end: LayoutPoint(x: 100, y: 0),
            transform: LayoutViewportTransform(), snapEnabled: false,
            optionKeyPressed: false
        )
        return controller
    }

    private func makeController(snapshot: LayoutSnapshot) -> LayoutEditorController {
        LayoutEditorController(
            document: LayoutEditorDocument(
                serverIdentity: "server",
                snapshot: snapshot,
                draftStore: LayoutDraftStoreSpyForTrackEditing(),
                autosaveDelayNanoseconds: 10_000_000_000
            )
        )
    }
}

private actor LayoutDraftStoreSpyForTrackEditing: LayoutDraftStoring {
    func load(serverIdentity: String) -> LayoutDraft? { nil }
    func save(_ draft: LayoutDraft) {}
    func delete(serverIdentity: String) {}
}
