import Foundation
import Testing
@testable import TrainPilot

@MainActor
struct LayoutIncompleteArchiveTests {
    @Test func omittedInversionIsFalseAndMissingAddressRemainsUnassigned() throws {
        let decoder = JSONDecoder()
        let endpoint = try decoder.decode(AccessoryEndpoint.self, from: Data(#"{"id":"main","linearAddress":12}"#.utf8))
        #expect(endpoint.linearAddress == 12)
        #expect(!endpoint.inverted)
        let missing = try decoder.decode(AccessoryEndpoint.self, from: Data(#"{"id":"main"}"#.utf8))
        #expect(missing.linearAddress == 0)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missing)) as? [String: Any]
        #expect(encoded?["linearAddress"] == nil)
    }

    @Test func archiveWithoutPresentationOrCantonsCanBeOpened() throws {
        let archive = ZIPContainer.write([
            "manifest.json": Data(#"{"formatVersion":1}"#.utf8),
            "layout.json": Data(#"{"layout":{"nodes":null,"turnouts":[{"id":"t1","kind":"simple","name":"Entrée","endpoints":[{"id":"main"}],"positions":[]}]}}"#.utf8)
        ])
        let contents = try LayoutStudioArchiveService().read(data: archive)
        #expect(contents.snapshot.topology.blocks.isEmpty)
        #expect(contents.snapshot.presentation.nodes.isEmpty)
        #expect(contents.turnouts.first?.endpoints.first?.linearAddress == 0)
        let session = LayoutStudioSession(snapshot: contents.snapshot, turnouts: contents.turnouts, canPublish: false)
        session.validateLocally()
        #expect(session.message?.contains("incomplet") == true)
        let saved = try LayoutStudioArchiveService().archive(for: session.controller.document, filename: "draft.dcclayout")
        let reopened = try LayoutStudioArchiveService().read(data: saved.data)
        #expect(reopened.turnouts == contents.turnouts)
    }

    @Test func removingAddressCanBeUndoneAndEmptyLayoutIsValid() throws {
        let session = LayoutStudioSession(canPublish: false)
        session.validateLocally()
        #expect(session.message == "Validation locale réussie.")
        let controller = session.controller
        try controller.addTurnout(
            id: "t1", kind: .simple, position: LayoutPoint(x: 0, y: 0),
            firstAddress: 12, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        let original = controller.document.turnoutDefinitions[0]
        try controller.configureTurnout(
            id: "t1", name: original.name,
            endpoints: [AccessoryEndpoint(id: "main", linearAddress: 0, inverted: false)],
            positions: original.positions
        )
        #expect(controller.document.turnoutDefinitions[0].endpoints[0].linearAddress == 0)
        session.validateLocally()
        #expect(session.message?.contains("incomplet") == true)
        controller.undo()
        #expect(controller.document.turnoutDefinitions[0] == original)
    }
}
