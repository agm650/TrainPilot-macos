import XCTest
@testable import TrainPilot

@MainActor
final class LayoutStudioTests: XCTestCase {
    func testAccessPolicyAllowsLocalUseAndAdministratorButRejectsDriver() {
        XCTAssertTrue(LayoutStudioAccessPolicy.canOpen(currentUser: nil))
        XCTAssertTrue(LayoutStudioAccessPolicy.canOpen(currentUser: makeUser(role: "administrator")))
        XCTAssertFalse(LayoutStudioAccessPolicy.canOpen(currentUser: makeUser(role: "driver")))
    }

    func testPublishingRequiresReadyAdministratorSession() {
        let administrator = makeUser(role: "administrator")
        XCTAssertTrue(
            LayoutStudioAccessPolicy.canPublish(
                currentUser: administrator,
                connectionState: .ready
            )
        )
        XCTAssertFalse(
            LayoutStudioAccessPolicy.canPublish(
                currentUser: administrator,
                connectionState: .disconnected
            )
        )
        XCTAssertFalse(
            LayoutStudioAccessPolicy.canPublish(
                currentUser: nil,
                connectionState: .ready
            )
        )
    }

    func testNewDocumentIsEmptyAndUsesDefaultGrid() {
        let session = LayoutStudioSession(canPublish: false)
        XCTAssertTrue(session.controller.document.topology.nodes.isEmpty)
        XCTAssertTrue(session.controller.document.topology.trackSections.isEmpty)
        XCTAssertTrue(session.controller.document.turnoutDefinitions.isEmpty)
        XCTAssertEqual(session.controller.document.presentation.gridSpacing, 20)
        XCTAssertEqual(session.controller.document.origin, .newLocal)
        XCTAssertNil(session.controller.document.baseTopologyRevision)
        XCTAssertNil(session.controller.document.basePresentationRevision)
    }

    func testOperationalRendererModeIsDistinctFromEditorMode() {
        XCTAssertNotEqual(
            LayoutInteractionMode.operationalReadOnly,
            .editor(showHandles: false)
        )
    }

    func testLocalArchiveRoundTrip() throws {
        let session = LayoutStudioSession(canPublish: false)
        let service = LayoutStudioArchiveService()
        let archive = try service.archive(
            for: session.controller.document,
            filename: "test.dcclayout"
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dcclayout")
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.data.write(to: url, options: .atomic)

        let contents = try service.read(from: url)
        XCTAssertEqual(contents.snapshot, LayoutStudioSession.emptySnapshot)
        XCTAssertTrue(contents.turnouts.isEmpty)
    }

    private func makeUser(role: String) -> User {
        User(
            id: UUID().uuidString,
            username: role,
            displayName: nil,
            role: role,
            enabled: true,
            mustChangePassword: false,
            createdAt: Date(),
            updatedAt: Date(),
            lastLoginAt: nil
        )
    }
}
