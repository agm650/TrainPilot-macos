import XCTest
import Testing
@testable import TrainPilot

@MainActor
struct LayoutArchiveCompatibilityTests {
    @Test func serverArchiveContract() throws {
        let session = LayoutStudioSession(canPublish: false)
        let archive = try LayoutStudioArchiveService().archive(
            for: session.controller.document, filename: "test.dcclayout"
        )
        let entries = try ZIPContainer.read(archive.data)
        let manifest = try #require(JSONSerialization.jsonObject(
            with: entries["manifest.json"] ?? Data()
        ) as? [String: Any])
        #expect(Set(manifest.keys) == ["format", "version", "packageType", "createdAt"])
        #expect(manifest["format"] as? String == "org.dcc-control.package")
        #expect(manifest["version"] as? Int == 7)
        #expect(manifest["packageType"] as? String == "layout")
        let createdAt = try #require(manifest["createdAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: createdAt) != nil)
        let root = try #require(JSONSerialization.jsonObject(
            with: entries["layout.json"] ?? Data()
        ) as? [String: Any])
        #expect(Set(root.keys) == ["layout"])
        let layout = try #require(root["layout"] as? [String: Any])
        let presentation = try #require(layout["presentation"] as? [String: Any])
        #expect(presentation["coordinateSystem"] as? String == "layout-units")
        #expect(presentation["revision"] == nil)
        #expect(layout["revision"] == nil)
    }

    @Test func legacyArchiveCanBeReopenedAndSaved() throws {
        let session = LayoutStudioSession(canPublish: false)
        let service = LayoutStudioArchiveService()
        let archive = try service.archive(for: session.controller.document, filename: "test.dcclayout")
        var entries = try ZIPContainer.read(archive.data)
        var root = try #require(JSONSerialization.jsonObject(
            with: entries["layout.json"] ?? Data()
        ) as? [String: Any])
        var layout = try #require(root["layout"] as? [String: Any])
        var presentation = try #require(layout.removeValue(forKey: "presentation") as? [String: Any])
        presentation["coordinateSystem"] = "cartesian"
        presentation["nodes"] = [["nodeId": "node-1", "x": 120, "y": 240]]
        layout["nodes"] = [["id": "node-1", "kind": "joint"]]
        root["layout"] = layout
        root["presentation"] = presentation
        entries["layout.json"] = try JSONSerialization.data(withJSONObject: root)
        entries["manifest.json"] = Data(#"{"formatVersion":1}"#.utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try ZIPContainer.write(entries).write(to: url)
        let contents = try service.read(from: url)
        #expect(contents.snapshot.presentation.coordinateSystem == "layout-units")
        let reopened = LayoutStudioSession(snapshot: contents.snapshot, turnouts: contents.turnouts, canPublish: false)
        let saved = try service.archive(for: reopened.controller.document, filename: "updated.dcclayout")
        try saved.data.write(to: url)
        let updated = try service.read(from: url)
        #expect(updated.snapshot == contents.snapshot)
        #expect(updated.turnouts == contents.turnouts)
    }
}

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

    func testLayoutTransferPolicyUsesServerSessionAndRole() {
        let administrator = makeUser(role: "administrator")
        let driver = makeUser(role: "driver")

        XCTAssertTrue(
            LayoutTransferPolicy.canImport(
                currentUser: administrator,
                connectionState: .ready
            )
        )
        XCTAssertFalse(
            LayoutTransferPolicy.canImport(
                currentUser: driver,
                connectionState: .ready
            )
        )
        XCTAssertTrue(
            LayoutTransferPolicy.canExport(
                currentUser: driver,
                connectionState: .ready
            )
        )
        XCTAssertFalse(
            LayoutTransferPolicy.canExport(
                currentUser: administrator,
                connectionState: .reconnecting
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
