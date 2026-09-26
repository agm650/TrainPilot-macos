import Combine
import Foundation

enum LayoutRevisionConflict: Equatable {
    case none
    case topologyChanged
    case presentationChanged
    case bothChanged
}

enum LayoutPublicationError: LocalizedError, Equatable {
    case administratorRequired
    case revisionConflict(LayoutRevisionConflict)
    case validationRequired
    case validationFailed
    case warningConfirmationRequired
    case publicationNotPending
    case canonicalRevisionNotConfirmed

    var errorDescription: String? {
        switch self {
        case .administratorRequired:
            return "La publication nécessite le rôle administrateur."
        case .revisionConflict(let conflict):
            switch conflict {
            case .none:
                return nil
            case .topologyChanged:
                return "La topologie publiée a changé depuis l’ouverture de l’éditeur."
            case .presentationChanged:
                return "La présentation publiée a changé depuis l’ouverture de l’éditeur."
            case .bothChanged:
                return "La topologie et la présentation publiées ont changé depuis l’ouverture de l’éditeur."
            }
        case .validationRequired:
            return "Validez le brouillon avant de le publier."
        case .validationFailed:
            return "La validation serveur a échoué."
        case .warningConfirmationRequired:
            return "Confirmez la publication malgré les avertissements."
        case .publicationNotPending:
            return "Aucune publication n’attend de confirmation serveur."
        case .canonicalRevisionNotConfirmed:
            return "Le serveur n’a pas encore confirmé de nouvelles révisions."
        }
    }
}

protocol LayoutPublicationAPI: Sendable {
    func exportLayout() async throws -> LayoutArchive
    func validateLayout(archive: Data, mode: LayoutImportMode) async throws -> LayoutValidationResult
    func importLayout(archive: Data, mode: LayoutImportMode) async throws
}

extension APIClient: LayoutPublicationAPI {}

@MainActor
final class LayoutPublicationCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case validating
        case validated(LayoutValidationResult)
        case importing
        case awaitingCanonicalRevisions
        case published
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var diagnostics: [LayoutValidationDiagnostic] = []

    private let api: any LayoutPublicationAPI
    private let archiveBuilder: LayoutArchiveBuilder
    private var validatedArchive: LayoutArchive?
    private var pendingBaseRevisions: (topology: String, presentation: String)?

    init(
        api: any LayoutPublicationAPI,
        archiveBuilder: LayoutArchiveBuilder = LayoutArchiveBuilder()
    ) {
        self.api = api
        self.archiveBuilder = archiveBuilder
    }

    static func revisionConflict(
        document: LayoutEditorDocument,
        serverSnapshot: LayoutSnapshot
    ) -> LayoutRevisionConflict {
        let topologyChanged =
            document.baseTopologyRevision != serverSnapshot.topology.revision
        let presentationChanged =
            document.basePresentationRevision != serverSnapshot.presentation.revision

        switch (topologyChanged, presentationChanged) {
        case (false, false):
            return .none
        case (true, false):
            return .topologyChanged
        case (false, true):
            return .presentationChanged
        case (true, true):
            return .bothChanged
        }
    }

    func validate(
        document: LayoutEditorDocument,
        serverSnapshot: LayoutSnapshot,
        allowingConflict: Bool = false
    ) async throws -> LayoutValidationResult {
        try checkConflict(
            document: document,
            serverSnapshot: serverSnapshot,
            allowingConflict: allowingConflict
        )
        try await document.prepareForValidationOrPublication()
        state = .validating
        document.setValidationState(.validating)

        do {
            let archive = try await makeDraftArchive(document: document)
            let result = try await api.validateLayout(
                archive: archive.data,
                mode: .replace
            )
            validatedArchive = result.valid ? archive : nil
            diagnostics = result.errors + result.warnings
            state = .validated(result)
            document.setValidationState(result.valid ? .valid(result) : .invalid(result))
            return result
        } catch {
            validatedArchive = nil
            state = .failed(error.localizedDescription)
            document.setValidationState(.notValidated)
            throw error
        }
    }

    func publish(
        document: LayoutEditorDocument,
        serverSnapshot: LayoutSnapshot,
        isAdministrator: Bool,
        allowingConflict: Bool = false,
        confirmingWarnings: Bool = false
    ) async throws {
        guard isAdministrator else {
            throw LayoutPublicationError.administratorRequired
        }
        try checkConflict(
            document: document,
            serverSnapshot: serverSnapshot,
            allowingConflict: allowingConflict
        )
        guard case .valid(let result) = document.validationState,
              result.valid,
              let archive = validatedArchive else {
            throw LayoutPublicationError.validationRequired
        }
        guard result.warnings.isEmpty || confirmingWarnings else {
            throw LayoutPublicationError.warningConfirmationRequired
        }

        state = .importing
        do {
            try await api.importLayout(archive: archive.data, mode: .replace)
            pendingBaseRevisions = (
                document.baseTopologyRevision,
                document.basePresentationRevision
            )
            state = .awaitingCanonicalRevisions
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func confirmCanonicalSnapshot(
        _ snapshot: LayoutSnapshot,
        document: LayoutEditorDocument
    ) async throws {
        guard let pendingBaseRevisions else {
            throw LayoutPublicationError.publicationNotPending
        }
        guard snapshot.topology.revision != pendingBaseRevisions.topology ||
                snapshot.presentation.revision != pendingBaseRevisions.presentation else {
            throw LayoutPublicationError.canonicalRevisionNotConfirmed
        }

        try await document.discardLocalDraft()
        self.pendingBaseRevisions = nil
        validatedArchive = nil
        state = .published
    }

    func exportDraft(document: LayoutEditorDocument) async throws -> LayoutArchive {
        try await document.prepareForValidationOrPublication()
        return try await makeDraftArchive(document: document)
    }

    func exportPublished() async throws -> LayoutArchive {
        try await api.exportLayout()
    }

    func selectionTarget(
        for diagnostic: LayoutValidationDiagnostic
    ) -> LayoutEditorSelection? {
        guard let id = diagnostic.resourceId else { return nil }
        switch diagnostic.resourceType {
        case "node":
            return .node(id)
        case "trackSection", "track_section":
            return .trackSection(id)
        case "turnout":
            return .turnout(id)
        case "block":
            return .block(id)
        default:
            return nil
        }
    }

    private func makeDraftArchive(
        document: LayoutEditorDocument
    ) async throws -> LayoutArchive {
        let serverArchive = try await api.exportLayout()
        return try archiveBuilder.build(
            from: serverArchive,
            document: document
        )
    }

    private func checkConflict(
        document: LayoutEditorDocument,
        serverSnapshot: LayoutSnapshot,
        allowingConflict: Bool
    ) throws {
        let conflict = Self.revisionConflict(
            document: document,
            serverSnapshot: serverSnapshot
        )
        if conflict != .none && !allowingConflict {
            throw LayoutPublicationError.revisionConflict(conflict)
        }
    }
}
