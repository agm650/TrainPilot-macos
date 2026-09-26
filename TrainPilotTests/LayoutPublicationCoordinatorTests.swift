import XCTest
@testable import TrainPilot

private actor PublicationDraftStore: LayoutDraftStoring {
    private var draft: LayoutDraft?
    private(set) var deleteCount = 0

    func load(serverIdentity: String) -> LayoutDraft? { draft }
    func save(_ draft: LayoutDraft) { self.draft = draft }
    func delete(serverIdentity: String) {
        draft = nil
        deleteCount += 1
    }

    func hasDraft() -> Bool { draft != nil }
}

private actor PublicationAPISpy: LayoutPublicationAPI {
    let archive: LayoutArchive
    var result: LayoutValidationResult
    var importError: Error?
    private(set) var importCount = 0

    init(archive: LayoutArchive, result: LayoutValidationResult) {
        self.archive = archive
        self.result = result
    }

    func exportLayout() -> LayoutArchive { archive }

    func validateLayout(
        archive: Data,
        mode: LayoutImportMode
    ) -> LayoutValidationResult {
        result
    }

    func importLayout(archive: Data, mode: LayoutImportMode) throws {
        if let importError { throw importError }
        importCount += 1
    }

    func setImportError(_ error: Error?) { importError = error }
    func imports() -> Int { importCount }
}

@MainActor
final class LayoutPublicationCoordinatorTests: XCTestCase {
    func testBuildArchivePreservesRoutesAndFeedbackMappings() throws {
        let document = makeDocument()
        let source = try makeServerArchive()
        let built = try LayoutArchiveBuilder().build(from: source, document: document)
        let entries = try ZIPContainer.read(built.data)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: XCTUnwrap(entries["layout.json"])
            ) as? [String: Any]
        )
        let layout = try XCTUnwrap(root["layout"] as? [String: Any])

        XCTAssertEqual((layout["routes"] as? [[String: Any]])?.first?["id"] as? String, "route-1")
        XCTAssertEqual(
            (layout["feedbackMappings"] as? [[String: Any]])?.first?["blockId"] as? String,
            "block-legacy"
        )
        XCTAssertNotNil(root["presentation"])
        XCTAssertEqual(built.suggestedFilename, "published-draft.dcclayout")
    }

    func testRevisionConflictReportsChangedResource() {
        let document = makeDocument()
        XCTAssertEqual(
            LayoutPublicationCoordinator.revisionConflict(
                document: document,
                serverSnapshot: makeEditorSnapshot(topologyRevision: "topology-2")
            ),
            .topologyChanged
        )
        XCTAssertEqual(
            LayoutPublicationCoordinator.revisionConflict(
                document: document,
                serverSnapshot: makeEditorSnapshot(
                    topologyRevision: "topology-2",
                    presentationRevision: "presentation-2"
                )
            ),
            .bothChanged
        )
    }

    func testValidationFailurePreventsImportAndKeepsDraft() async throws {
        let store = PublicationDraftStore()
        let document = makeDocument(store: store)
        let api = PublicationAPISpy(
            archive: try makeServerArchive(),
            result: LayoutValidationResult(
                valid: false,
                errors: [
                    LayoutValidationDiagnostic(
                        code: "invalid_track",
                        resourceType: "trackSection",
                        resourceId: "track-1",
                        message: "Invalid"
                    )
                ],
                warnings: []
            )
        )
        let coordinator = LayoutPublicationCoordinator(api: api)

        let result = try await coordinator.validate(
            document: document,
            serverSnapshot: makeEditorSnapshot()
        )
        XCTAssertFalse(result.valid)
        await XCTAssertThrowsErrorAsync {
            try await coordinator.publish(
                document: document,
                serverSnapshot: makeEditorSnapshot(),
                isAdministrator: true
            )
        }
        let importCount = await api.imports()
        let hasDraft = await store.hasDraft()
        XCTAssertEqual(importCount, 0)
        XCTAssertTrue(hasDraft)
        XCTAssertEqual(
            coordinator.selectionTarget(for: result.errors[0]),
            LayoutEditorSelection.trackSection("track-1")
        )
    }

    func testWarningRequiresExplicitConfirmation() async throws {
        let document = makeDocument()
        let api = PublicationAPISpy(
            archive: try makeServerArchive(),
            result: LayoutValidationResult(
                valid: true,
                errors: [],
                warnings: [
                    LayoutValidationDiagnostic(
                        code: "warning",
                        resourceType: nil,
                        resourceId: nil,
                        message: "Review"
                    )
                ]
            )
        )
        let coordinator = LayoutPublicationCoordinator(api: api)
        _ = try await coordinator.validate(
            document: document,
            serverSnapshot: makeEditorSnapshot()
        )

        await XCTAssertThrowsErrorAsync {
            try await coordinator.publish(
                document: document,
                serverSnapshot: makeEditorSnapshot(),
                isAdministrator: true
            )
        }
        try await coordinator.publish(
            document: document,
            serverSnapshot: makeEditorSnapshot(),
            isAdministrator: true,
            confirmingWarnings: true
        )
        let importCount = await api.imports()
        XCTAssertEqual(importCount, 1)
        XCTAssertEqual(coordinator.state, .awaitingCanonicalRevisions)
    }

    func testSuccessfulImportWaitsForRevisionsBeforeCleanup() async throws {
        let store = PublicationDraftStore()
        let document = makeDocument(store: store)
        let api = PublicationAPISpy(
            archive: try makeServerArchive(),
            result: LayoutValidationResult(valid: true, errors: [], warnings: [])
        )
        let coordinator = LayoutPublicationCoordinator(api: api)
        _ = try await coordinator.validate(
            document: document,
            serverSnapshot: makeEditorSnapshot()
        )
        try await coordinator.publish(
            document: document,
            serverSnapshot: makeEditorSnapshot(),
            isAdministrator: true
        )

        var hasDraft = await store.hasDraft()
        XCTAssertTrue(hasDraft)
        await XCTAssertThrowsErrorAsync {
            try await coordinator.confirmCanonicalSnapshot(
                makeEditorSnapshot(),
                document: document
            )
        }
        hasDraft = await store.hasDraft()
        XCTAssertTrue(hasDraft)

        try await coordinator.confirmCanonicalSnapshot(
            makeEditorSnapshot(
                topologyRevision: "topology-2",
                presentationRevision: "presentation-2"
            ),
            document: document
        )
        hasDraft = await store.hasDraft()
        XCTAssertFalse(hasDraft)
        XCTAssertEqual(coordinator.state, .published)
    }

    func testImportFailureKeepsDraft() async throws {
        let store = PublicationDraftStore()
        let document = makeDocument(store: store)
        let api = PublicationAPISpy(
            archive: try makeServerArchive(),
            result: LayoutValidationResult(valid: true, errors: [], warnings: [])
        )
        await api.setImportError(APIError.httpStatus(500))
        let coordinator = LayoutPublicationCoordinator(api: api)
        _ = try await coordinator.validate(
            document: document,
            serverSnapshot: makeEditorSnapshot()
        )

        await XCTAssertThrowsErrorAsync {
            try await coordinator.publish(
                document: document,
                serverSnapshot: makeEditorSnapshot(),
                isAdministrator: true
            )
        }
        let hasDraft = await store.hasDraft()
        XCTAssertTrue(hasDraft)
    }

    func testDraftFilenameIsClearAndStable() {
        XCTAssertEqual(
            LayoutArchiveBuilder.draftFilename(from: "network.dcclayout"),
            "network-draft.dcclayout"
        )
        XCTAssertEqual(
            LayoutArchiveBuilder.draftFilename(from: ""),
            "TrainPilot-layout-draft.dcclayout"
        )
    }

    private func makeDocument(
        store: any LayoutDraftStoring = PublicationDraftStore()
    ) -> LayoutEditorDocument {
        LayoutEditorDocument(
            serverIdentity: "server-a",
            snapshot: makeEditorSnapshot(),
            draftStore: store,
            autosaveDelayNanoseconds: 10_000_000_000
        )
    }

    private func makeServerArchive() throws -> LayoutArchive {
        let manifest: [String: Any] = [
            "format": "org.dcc-control.package",
            "version": 6,
            "packageType": "layout",
            "createdAt": "2026-09-26T00:00:00Z"
        ]
        let layout: [String: Any] = [
            "layout": [
                "nodes": [],
                "trackSections": [],
                "turnoutTopologies": [],
                "blocks": [],
                "turnouts": [],
                "routes": [["id": "route-1"]],
                "feedbackMappings": [
                    ["provider": "rbus", "address": 1, "blockId": "block-legacy"]
                ]
            ],
            "presentation": ["gridSpacing": 10]
        ]
        return LayoutArchive(
            data: ZIPContainer.write([
                "manifest.json": try JSONSerialization.data(withJSONObject: manifest),
                "layout.json": try JSONSerialization.data(withJSONObject: layout)
            ]),
            suggestedFilename: "published.dcclayout"
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}
