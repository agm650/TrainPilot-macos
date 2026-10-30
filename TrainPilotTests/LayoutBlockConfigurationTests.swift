import Foundation
import Testing
@testable import TrainPilot

@MainActor
struct LayoutBlockConfigurationTests {
    private func controller() throws -> LayoutEditorController {
        let controller = LayoutStudioSession(canPublish: false).controller
        let nodes = [
            TopologyNode(id: "a", name: nil, kind: .joint),
            TopologyNode(id: "b", name: nil, kind: .joint),
            TopologyNode(id: "c", name: nil, kind: .joint)
        ]
        let tracks = [
            TrackSection(id: "ab", name: "AB", nodeAId: "a", nodeBId: "b", lengthMm: nil),
            TrackSection(id: "bc", name: "BC", nodeAId: "b", nodeBId: "c", lengthMm: nil)
        ]
        controller.document.replaceTopology(controller.document.topology.replacing(nodes: nodes, trackSections: tracks))
        controller.select(.trackSection("ab"))
        return controller
    }

    @Test func configurationSurvivesUndoArchiveAndDraft() async throws {
        let controller = try controller()
        try controller.createBlockFromSelection()
        let block = try #require(controller.document.topology.blocks.first)
        try controller.configureBlock(id: block.id, name: "Gare 1", source: "z21-rbus", address: "17")
        #expect(controller.document.topology.feedbackMappings?.first?.address == 17)
        controller.undo()
        #expect(controller.document.topology.feedbackMappings == nil)
        controller.redo()
        let archive = try LayoutStudioArchiveService().archive(for: controller.document, filename: "test.dcclayout")
        let loaded = try LayoutStudioArchiveService().read(data: archive.data)
        #expect(loaded.snapshot.topology.feedbackMappings == controller.document.topology.feedbackMappings)
        #expect(loaded.snapshot.topology.blocks.first?.name == "Gare 1")
        let built = try LayoutArchiveBuilder().build(from: archive, document: controller.document)
        let published = try LayoutStudioArchiveService().read(data: built.data)
        #expect(published.snapshot.topology.feedbackMappings?.first?.address == 17)
        try await controller.document.saveNow()
        controller.select(.block(block.id))
        try controller.deleteSelection()
        #expect(controller.document.topology.feedbackMappings?.isEmpty == true)
        controller.undo()
        #expect(controller.document.topology.feedbackMappings?.first?.address == 17)
    }

    @Test func rejectsAlreadyGroupedSectionsAndDuplicateContacts() throws {
        let controller = try controller()
        try controller.createBlockFromSelection()
        let first = try #require(controller.document.topology.blocks.first)
        try controller.configureBlock(id: first.id, name: "A", source: "z21-rbus", address: "3")
        controller.select(.trackSection("ab"))
        #expect(throws: TurnoutConfigurationError.self) { try controller.createBlockFromSelection() }
        controller.select(.trackSection("bc"))
        try controller.createBlockFromSelection()
        let second = try #require(controller.document.topology.blocks.last)
        #expect(throws: TurnoutConfigurationError.self) {
            try controller.configureBlock(id: second.id, name: "B", source: "z21-rbus", address: "3")
        }
        #expect(throws: TurnoutConfigurationError.self) {
            try controller.configureBlock(id: second.id, name: "B", source: "z21-rbus", address: "0")
        }
    }

    @Test func groupsMultipleSectionsAsOneUndoableOperation() throws {
        let controller = try controller()
        controller.selectElements([.trackSection("ab"), .trackSection("bc")])
        try controller.createBlockFromSelection()
        #expect(controller.document.topology.blocks.first?.trackSectionIds == ["ab", "bc"])
        #expect(controller.document.presentation.blocks.count == 1)
        controller.undo()
        #expect(controller.document.topology.blocks.isEmpty)
        #expect(controller.document.presentation.blocks.isEmpty)
        controller.redo()
        #expect(controller.document.topology.blocks.first?.trackSectionIds == ["ab", "bc"])
    }

    @Test func rejectsDisconnectedAndMixedSelectionsWithoutMutation() throws {
        let controller = try controller()
        let detached = TrackSection(id: "de", name: "DE", nodeAId: "d", nodeBId: "e", lengthMm: nil)
        controller.document.replaceTopology(controller.document.topology.replacing(
            nodes: controller.document.topology.nodes + [
                TopologyNode(id: "d", name: nil, kind: .joint),
                TopologyNode(id: "e", name: nil, kind: .joint)
            ],
            trackSections: controller.document.topology.trackSections + [detached]
        ))
        let original = controller.document.topology
        for selection: Set<LayoutEditorSelection> in [
            [], [.trackSection("ab"), .trackSection("de")],
            [.trackSection("ab"), .node("a")]
        ] {
            controller.selectElements(selection)
            #expect(throws: TurnoutConfigurationError.self) { try controller.createBlockFromSelection() }
            #expect(controller.document.topology == original)
        }
    }

    @Test func publishedArchiveRemovesDeletedContact() throws {
        let controller = try controller()
        try controller.createBlockFromSelection()
        let block = try #require(controller.document.topology.blocks.first)
        try controller.configureBlock(id: block.id, name: "Gare", source: "z21-rbus", address: "17")
        let original = try LayoutStudioArchiveService().archive(for: controller.document, filename: "test.dcclayout")
        controller.select(.block(block.id))
        try controller.deleteSelection()
        let built = try LayoutArchiveBuilder().build(from: original, document: controller.document)
        let contents = try LayoutStudioArchiveService().read(data: built.data)
        #expect(contents.snapshot.topology.blocks.isEmpty)
        #expect(contents.snapshot.topology.feedbackMappings?.isEmpty == true)
    }

    @Test func savedDraftActuallyRestoresDetectionConfiguration() async throws {
        let controller = try controller()
        try controller.createBlockFromSelection()
        let block = try #require(controller.document.topology.blocks.first)
        try controller.configureBlock(id: block.id, name: "Gare", source: "z21-rbus", address: "17")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LayoutDraftStore(directoryURL: directory)
        let document = LayoutEditorDocument(
            serverIdentity: "test-server",
            snapshot: LayoutSnapshot(topology: controller.document.topology, presentation: controller.document.presentation),
            draftStore: store
        )
        try await document.saveNow()
        let loaded = try await store.load(serverIdentity: "test-server")
        let draft = try #require(loaded)
        let restored = LayoutEditorDocument(draft: draft, draftStore: store)
        #expect(restored.topology == document.topology)
        #expect(restored.topology.feedbackMappings?.first?.address == 17)
        #expect(!restored.isDirty)
    }

    @Test(arguments: [false, true])
    func rbusPairMustBeUniqueAcrossCantonsAfterReopening(_ genericMapping: Bool) throws {
        let controller = try controller()
        try controller.createBlockFromSelection()
        let first = try #require(controller.document.topology.blocks.first)
        let address = try RBusContactAddress(detector: 3, input: 5).globalAddress()
        try controller.configureBlock(id: first.id, name: "Gare", source: "z21-rbus", address: String(address))
        controller.select(.trackSection("bc"))
        try controller.createBlockFromSelection()
        let second = try #require(controller.document.topology.blocks.last)
        if genericMapping {
            var topology = controller.document.topology
            topology.feedbackMappings = []
            topology.occupancySensorMappings = [
                LayoutSensorMapping(providerId: "z21-rbus", sensorId: String(address), blockId: first.id)
            ]
            controller.document.replaceTopology(topology)
        }
        let archive = try LayoutStudioArchiveService().archive(for: controller.document, filename: "test.dcclayout")
        let contents = try LayoutStudioArchiveService().read(data: archive.data)
        let reopened = LayoutStudioSession(snapshot: contents.snapshot, canPublish: false).controller
        let before = reopened.document.topology
        do {
            try reopened.configureBlock(id: second.id, name: "Autre", source: "z21-rbus", address: String(address))
            Issue.record("A duplicate detector/input pair must be rejected")
        } catch {
            #expect(error.localizedDescription.contains("détecteur 3, entrée 5"))
            #expect(error.localizedDescription.contains("Gare"))
        }
        #expect(reopened.document.topology == before)
        // Keeping a contact on its own canton and using another input remain valid.
        try reopened.configureBlock(id: first.id, name: "Gare", source: "z21-rbus", address: String(address))
        let next = try RBusContactAddress(detector: 3, input: 6).globalAddress()
        try reopened.configureBlock(id: second.id, name: "Autre", source: "z21-rbus", address: String(next))
        #expect(reopened.document.topology.feedbackMappings?.count == 2)
    }

    @Test func occupancyIncludesFreeAndMissingIsUnknown() {
        let runtime = TopologyRuntimeState(blockOccupancy: ["free": .free, "occupied": .occupied], turnoutStates: [:])
        #expect(runtime.occupancyEmphasis(for: []) == .none)
        #expect(runtime.occupancyEmphasis(for: ["missing"]) == .unknown)
        #expect(runtime.occupancyEmphasis(for: ["free"]) == .free)
        #expect(runtime.occupancyEmphasis(for: ["occupied"]) == .occupied)
        #expect(runtime.occupancyEmphasis(for: ["missing", "occupied"]) == .occupied)
    }
}
