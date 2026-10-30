import Foundation
import Testing
@testable import TrainPilot

private actor GuardAPI: LayoutPublicationAPI {
    private(set) var calls = 0
    func exportLayout() throws -> LayoutArchive {
        calls += 1
        throw LayoutArchiveError.invalidArchive
    }
    func validateLayout(archive: Data, mode: LayoutImportMode) -> LayoutValidationResult {
        calls += 1
        return LayoutValidationResult(valid: true, errors: [], warnings: [])
    }
    func importLayout(archive: Data, mode: LayoutImportMode) { calls += 1 }
}

@MainActor
struct LayoutPublicationGuardTests {
    @Test func unassignedAddressBlocksNetworkValidationAndImport() async throws {
        let session = LayoutStudioSession(canPublish: true)
        try session.controller.addTurnout(
            id: "t1", kind: .simple, position: LayoutPoint(x: 0, y: 0),
            firstAddress: 0, transform: LayoutViewportTransform(),
            snapEnabled: false, optionKeyPressed: false
        )
        let api = GuardAPI()
        let coordinator = LayoutPublicationCoordinator(api: api)
        do {
            _ = try await coordinator.validate(document: session.controller.document, serverSnapshot: LayoutStudioSession.emptySnapshot)
            Issue.record("An unassigned address must block publication")
        } catch is StudioPublicationError {
            // Expected before any network request.
        }
        #expect(await api.calls == 0)
    }

    @Test func publishWithoutValidationOrAdministratorDoesNotImport() async throws {
        let session = LayoutStudioSession(canPublish: true)
        let api = GuardAPI()
        let coordinator = LayoutPublicationCoordinator(api: api)
        for administrator in [false, true] {
            do {
                try await coordinator.publish(
                    document: session.controller.document,
                    serverSnapshot: LayoutStudioSession.emptySnapshot,
                    isAdministrator: administrator
                )
                Issue.record("Publication requires authorization and validation")
            } catch let error as LayoutPublicationError {
                #expect(error == (administrator ? .validationRequired : .administratorRequired))
            }
        }
        #expect(await api.calls == 0)
    }
}
