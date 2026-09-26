import Foundation
import XCTest
@testable import TrainPilot

final class LayoutDraftStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    func testSaveAndLoadRoundTrip() async throws {
        let store = makeStore()
        let draft = makeDraft(serverIdentity: "https://layout.example/")

        try await store.save(draft)
        let loaded = try await store.load(serverIdentity: draft.serverIdentity)

        XCTAssertEqual(loaded, draft)
    }

    func testDraftFromAnotherServerIsNotLoaded() async throws {
        let store = makeStore()
        let draft = makeDraft(serverIdentity: "https://first.example/")
        try await store.save(draft)

        let loaded = try await store.load(
            serverIdentity: "https://second.example/"
        )

        XCTAssertNil(loaded)
    }

    func testUnknownFormatIsRejected() async throws {
        let (store, directory) = makeStoreAndDirectory()
        let draft = makeDraft(serverIdentity: "https://layout.example/")
        try await store.save(draft)
        let fileURL = try onlyDraftFile(in: directory)
        let unknownFormat = """
        { "draftFormatVersion": 999 }
        """
        try Data(unknownFormat.utf8).write(to: fileURL, options: .atomic)

        do {
            _ = try await store.load(serverIdentity: draft.serverIdentity)
            XCTFail("An unknown draft format should be rejected")
        } catch let error as LayoutDraftStoreError {
            XCTAssertEqual(error, .unsupportedFormat(999))
        }
    }

    func testCorruptedFileIsRejected() async throws {
        let (store, directory) = makeStoreAndDirectory()
        let draft = makeDraft(serverIdentity: "https://layout.example/")
        try await store.save(draft)
        let fileURL = try onlyDraftFile(in: directory)
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        do {
            _ = try await store.load(serverIdentity: draft.serverIdentity)
            XCTFail("A corrupted draft should be rejected")
        } catch let error as LayoutDraftStoreError {
            XCTAssertEqual(error, .corrupted)
        }
    }

    func testPersistedDraftContainsNoSensitiveAuthenticationData() async throws {
        let (store, directory) = makeStoreAndDirectory()
        let draft = makeDraft(serverIdentity: "https://layout.example/")
        try await store.save(draft)

        let data = try Data(contentsOf: onlyDraftFile(in: directory))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.localizedCaseInsensitiveContains("accessToken"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("refreshToken"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("password"))
    }

    private func makeStore() -> LayoutDraftStore {
        makeStoreAndDirectory().store
    }

    private func makeStoreAndDirectory() -> (
        store: LayoutDraftStore,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        return (LayoutDraftStore(directoryURL: directory), directory)
    }

    private func onlyDraftFile(in directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try XCTUnwrap(files.first)
    }
}

func makeDraft(serverIdentity: String) -> LayoutDraft {
    LayoutDraft(
        draftFormatVersion: LayoutDraft.currentFormatVersion,
        serverIdentity: serverIdentity,
        baseTopologyRevision: "topology-1",
        basePresentationRevision: "presentation-1",
        savedAt: Date(timeIntervalSince1970: 1_000),
        topology: makeEditorSnapshot().topology,
        presentation: makeEditorSnapshot().presentation,
        turnouts: nil
    )
}

func makeEditorSnapshot(
    topologyRevision: String = "topology-1",
    presentationRevision: String = "presentation-1"
) -> LayoutSnapshot {
    LayoutSnapshot(
        topology: TopologyDefinition(
            revision: topologyRevision,
            nodes: [],
            trackSections: [],
            turnoutTopologies: [],
            blocks: []
        ),
        presentation: LayoutPresentationDefinition(
            revision: presentationRevision,
            coordinateSystem: "layout-units",
            gridSpacing: 20,
            nodes: [],
            trackSections: [],
            turnouts: [],
            blocks: []
        )
    )
}
