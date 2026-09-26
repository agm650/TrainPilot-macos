import XCTest
@testable import TrainPilot

private actor LayoutDraftStoreSpy: LayoutDraftStoring {
    var draft: LayoutDraft?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    func load(serverIdentity: String) -> LayoutDraft? {
        guard draft?.serverIdentity == serverIdentity else { return nil }
        return draft
    }

    func save(_ draft: LayoutDraft) {
        self.draft = draft
        saveCount += 1
    }

    func delete(serverIdentity: String) {
        if draft?.serverIdentity == serverIdentity {
            draft = nil
        }
        deleteCount += 1
    }

    func counts() -> (save: Int, delete: Int) {
        (saveCount, deleteCount)
    }

    func currentDraft() -> LayoutDraft? {
        draft
    }
}

@MainActor
final class LayoutEditorDocumentTests: XCTestCase {
    func testCreatesDraftFromServerWhenNoLocalDraftExists() async throws {
        let store = LayoutDraftStoreSpy()

        let result = try await LayoutEditorDocument.open(
            serverIdentity: "server-a",
            serverSnapshot: makeEditorSnapshot(),
            draftStore: store
        )

        guard case .created(let document) = result else {
            return XCTFail("Expected a new editor document")
        }
        XCTAssertEqual(document.baseTopologyRevision, "topology-1")
        XCTAssertEqual(document.basePresentationRevision, "presentation-1")
        XCTAssertFalse(document.isDirty)
    }

    func testMatchingDraftIsResumed() async throws {
        let store = LayoutDraftStoreSpy()
        await store.save(makeDraft(serverIdentity: "server-a"))

        let result = try await LayoutEditorDocument.open(
            serverIdentity: "server-a",
            serverSnapshot: makeEditorSnapshot(),
            draftStore: store
        )

        guard case .resumed(let document) = result else {
            return XCTFail("Expected the matching draft to resume")
        }
        XCTAssertEqual(document.lastLocalSaveDate, Date(timeIntervalSince1970: 1_000))
    }

    func testDivergentDraftRequiresExplicitResolution() async throws {
        let store = LayoutDraftStoreSpy()
        await store.save(makeDraft(serverIdentity: "server-a"))

        let result = try await LayoutEditorDocument.open(
            serverIdentity: "server-a",
            serverSnapshot: makeEditorSnapshot(topologyRevision: "topology-2"),
            draftStore: store
        )

        guard case .conflict(let conflict) = result else {
            return XCTFail("Expected an explicit revision conflict")
        }
        let resolved = try await LayoutEditorDocument.resolve(
            conflict,
            resolution: .resumeDraft,
            draftStore: store
        )
        let resumed = try XCTUnwrap(resolved)
        XCTAssertEqual(
            resumed.serverState,
            .changed(
                topologyRevision: "topology-2",
                presentationRevision: "presentation-1"
            )
        )
    }

    func testMutationSetsDirtyFlagAndExplicitSaveClearsIt() async throws {
        let store = LayoutDraftStoreSpy()
        let document = LayoutEditorDocument(
            serverIdentity: "server-a",
            snapshot: makeEditorSnapshot(),
            draftStore: store,
            autosaveDelayNanoseconds: 10_000_000_000
        )
        let changed = makeEditorSnapshot(presentationRevision: "working-copy")

        document.replacePresentation(changed.presentation)
        XCTAssertTrue(document.isDirty)

        try await document.saveNow()
        XCTAssertFalse(document.isDirty)
        XCTAssertNotNil(document.lastLocalSaveDate)
        let counts = await store.counts()
        XCTAssertEqual(counts.save, 1)
    }

    func testAutosaveIsDebouncedAfterMutations() async throws {
        let store = LayoutDraftStoreSpy()
        let document = LayoutEditorDocument(
            serverIdentity: "server-a",
            snapshot: makeEditorSnapshot(),
            draftStore: store,
            autosaveDelayNanoseconds: 20_000_000
        )

        document.replacePresentation(
            makeEditorSnapshot(presentationRevision: "working-1").presentation
        )
        document.replacePresentation(
            makeEditorSnapshot(presentationRevision: "working-2").presentation
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        let counts = await store.counts()
        XCTAssertEqual(counts.save, 1)
        XCTAssertFalse(document.isDirty)
    }

    func testFailedValidationDoesNotDeleteDraft() async throws {
        let store = LayoutDraftStoreSpy()
        let document = LayoutEditorDocument(
            serverIdentity: "server-a",
            snapshot: makeEditorSnapshot(),
            draftStore: store
        )
        document.replacePresentation(
            makeEditorSnapshot(presentationRevision: "working-copy").presentation
        )
        try await document.prepareForValidationOrPublication()
        document.setValidationState(
            .invalid(
                LayoutValidationResult(
                    valid: false,
                    errors: [],
                    warnings: []
                )
            )
        )

        let counts = await store.counts()
        let savedDraft = await store.currentDraft()
        XCTAssertEqual(counts.delete, 0)
        XCTAssertNotNil(savedDraft)
    }
}
