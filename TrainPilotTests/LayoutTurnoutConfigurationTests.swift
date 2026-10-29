import Foundation
import Testing
@testable import TrainPilot

@MainActor
struct LayoutTurnoutConfigurationTests {
    private func controller(kind: TurnoutKind) throws -> LayoutEditorController {
        let session = LayoutStudioSession(canPublish: false)
        let controller = session.controller
        try controller.addTurnout(
            id: "t1", kind: kind, position: LayoutPoint(x: 0, y: 0),
            firstAddress: 1, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        return controller
    }

    @Test(arguments: [TurnoutKind.simple, .threeWay, .doubleSlip])
    func configurationIsAtomicAndPreservedInArchive(_ kind: TurnoutKind) throws {
        let controller = try controller(kind: kind)
        let original = controller.document.turnoutDefinitions[0]
        let topology = controller.document.topology
        let presentation = controller.document.presentation
        let endpoints = original.endpoints.enumerated().map {
            AccessoryEndpoint(id: $0.element.id, linearAddress: 100 + $0.offset * 7, inverted: true)
        }
        // Swapping whole vectors must be allowed even though intermediate vectors would duplicate.
        let positions = zip(original.positions, original.positions.reversed()).map {
            TurnoutPositionDefinition(id: $0.0.id, label: $0.0.label, endpoints: $0.1.endpoints)
        }
        try controller.configureTurnout(id: "t1", name: " Entrée gare ", endpoints: endpoints, positions: positions)
        let updated = controller.document.turnoutDefinitions[0]
        #expect(updated.name == "Entrée gare")
        #expect(updated.endpoints == endpoints)
        #expect(updated.positions == positions)
        #expect(controller.document.topology == topology)
        #expect(controller.document.presentation == presentation)
        controller.undo()
        #expect(controller.document.turnoutDefinitions[0] == original)
        controller.redo()
        #expect(controller.document.turnoutDefinitions[0] == updated)

        let archive = try LayoutStudioArchiveService().archive(for: controller.document, filename: "test.dcclayout")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.data.write(to: url)
        let contents = try LayoutStudioArchiveService().read(from: url)
        #expect(contents.turnouts == [updated])
    }

    @Test func invalidConfigurationsDoNotMutateTheDocument() throws {
        let controller = try controller(kind: .threeWay)
        let original = controller.document.turnoutDefinitions[0]
        let invalidEndpoints = [
            [AccessoryEndpoint(id: "a", linearAddress: 0, inverted: false),
             AccessoryEndpoint(id: "b", linearAddress: 2041, inverted: false)],
            [AccessoryEndpoint(id: "a", linearAddress: 12, inverted: false),
             AccessoryEndpoint(id: "b", linearAddress: 12, inverted: false)]
        ]
        for endpoints in invalidEndpoints {
            #expect(throws: TurnoutConfigurationError.self) {
                try controller.configureTurnout(id: "t1", name: original.name, endpoints: endpoints, positions: original.positions)
            }
        }
        let duplicates = original.positions.map {
            TurnoutPositionDefinition(id: $0.id, label: $0.label, endpoints: original.positions[0].endpoints)
        }
        #expect(throws: TurnoutConfigurationError.self) {
            try controller.configureTurnout(id: "t1", name: original.name, endpoints: original.endpoints, positions: duplicates)
        }
        #expect(throws: TurnoutConfigurationError.self) {
            try controller.configureTurnout(id: "t1", name: "  ", endpoints: original.endpoints, positions: original.positions)
        }
        #expect(controller.document.turnoutDefinitions == [original])
    }

    @Test func addressAlreadyAssignedToAnotherTurnoutIsRejected() throws {
        let controller = try controller(kind: .simple)
        try controller.addTurnout(
            id: "t2", kind: .simple, position: LayoutPoint(x: 100, y: 0),
            firstAddress: 20, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        let original = controller.document.turnoutDefinitions
        #expect(throws: TurnoutConfigurationError.self) {
            try controller.configureTurnout(
                id: "t1", name: "Entrée",
                endpoints: [AccessoryEndpoint(id: "main", linearAddress: 20, inverted: false)],
                positions: original[0].positions
            )
        }
        #expect(controller.document.turnoutDefinitions == original)
    }
}
