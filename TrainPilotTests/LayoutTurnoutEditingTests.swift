import XCTest
@testable import TrainPilot

@MainActor
final class LayoutTurnoutEditingTests: XCTestCase {
    func testCreatesSimpleAndInvertedTurnout() throws {
        let controller = makeController()
        try controller.addTurnout(
            id: "t1", kind: .simple, position: LayoutPoint(x: 43, y: 57),
            firstAddress: 12, transform: LayoutViewportTransform(),
            snapEnabled: true, optionKeyPressed: false
        )
        try controller.updateTurnoutEndpoint(
            turnoutID: "t1", endpointID: "main",
            linearAddress: 12, inverted: true
        )

        XCTAssertEqual(controller.document.turnoutDefinitions[0].kind, .simple)
        XCTAssertTrue(controller.document.turnoutDefinitions[0].endpoints[0].inverted)
        XCTAssertEqual(controller.document.presentation.turnouts[0].x, 40)
        XCTAssertEqual(controller.document.topology.turnoutTopologies[0].ports.count, 3)
    }

    func testCreatesAllEditableKindsAndKeepsCustomReadOnly() throws {
        let controller = makeController()
        for (index, kind) in [TurnoutKind.threeWay, .doubleSlip, .singleSlip].enumerated() {
            try controller.addTurnout(
                id: "t\(index)", kind: kind,
                position: LayoutPoint(x: Double(index) * 100, y: 0),
                firstAddress: 20 + index * 2,
                transform: LayoutViewportTransform(),
                snapEnabled: false, optionKeyPressed: false
            )
        }

        XCTAssertEqual(controller.document.turnoutDefinitions.map(\.kind), [
            .threeWay, .doubleSlip, .singleSlip
        ])
        XCTAssertEqual(
            TurnoutPaletteItem.all.first(where: { $0.kind == .custom })?.isEditable,
            false
        )
    }

    func testRotationAndMirrorDoNotChangeDCCMapping() throws {
        let controller = makeController()
        try controller.addTurnout(
            id: "t1", kind: .simple, position: LayoutPoint(x: 0, y: 0),
            firstAddress: 7, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        let definition = controller.document.turnoutDefinitions[0]

        try controller.transformTurnout(id: "t1", rotationDegrees: 90, mirrored: true)

        XCTAssertEqual(controller.document.turnoutDefinitions[0], definition)
        XCTAssertEqual(controller.document.presentation.turnouts[0].rotationDegrees, 90)
        XCTAssertTrue(controller.document.presentation.turnouts[0].mirrored)
    }

    func testPropertyChangesSupportUndoRedo() throws {
        let controller = makeController()
        try controller.addTurnout(
            id: "t1", kind: .simple, position: LayoutPoint(x: 0, y: 0),
            firstAddress: 7, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        try controller.updateTurnoutEndpoint(
            turnoutID: "t1", endpointID: "main",
            linearAddress: 42, inverted: true
        )
        controller.undo()
        XCTAssertEqual(controller.document.turnoutDefinitions[0].endpoints[0].linearAddress, 7)
        controller.redo()
        XCTAssertEqual(controller.document.turnoutDefinitions[0].endpoints[0].linearAddress, 42)
    }

    func testValidatorDetectsDuplicateAddress() throws {
        let controller = makeController()
        for id in ["t1", "t2"] {
            try controller.addTurnout(
                id: id, kind: .simple, position: LayoutPoint(x: 0, y: 0),
                firstAddress: 12, transform: LayoutViewportTransform(),
                snapEnabled: false, optionKeyPressed: false
            )
        }
        let issues = TurnoutValidator().validate(
            definitions: controller.document.turnoutDefinitions,
            topology: controller.document.topology,
            presentation: controller.document.presentation
        )
        XCTAssertTrue(issues.contains(.duplicateAddress(12)))
    }

    func testDefinitionSerializationRoundTrip() throws {
        let definition = TurnoutDefinition(
            id: "t1", name: "Entrée", kind: .simple,
            endpoints: [AccessoryEndpoint(id: "main", linearAddress: 10, inverted: true)],
            positions: [
                TurnoutPositionDefinition(
                    id: "straight", label: "Droit", endpoints: ["main": .position1]
                )
            ]
        )
        let data = try JSONEncoder().encode(definition)
        XCTAssertEqual(try JSONDecoder().decode(TurnoutDefinition.self, from: data), definition)
    }

    private func makeController() -> LayoutEditorController {
        LayoutEditorController(
            document: LayoutEditorDocument(
                serverIdentity: "server",
                snapshot: makeEditorSnapshot(),
                draftStore: LayoutDraftStoreSpyForTurnoutEditing(),
                autosaveDelayNanoseconds: 10_000_000_000
            )
        )
    }
}

private actor LayoutDraftStoreSpyForTurnoutEditing: LayoutDraftStoring {
    func load(serverIdentity: String) -> LayoutDraft? { nil }
    func save(_ draft: LayoutDraft) {}
    func delete(serverIdentity: String) {}
}
