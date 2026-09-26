import Combine
import Foundation

enum LayoutEditorServerState: Equatable {
    case matchesBase
    case changed(topologyRevision: String, presentationRevision: String)
    case unavailable
}

enum LayoutEditorValidationState: Equatable {
    case notValidated
    case validating
    case valid(LayoutValidationResult)
    case invalid(LayoutValidationResult)
}

enum LayoutDraftConflictResolution: Equatable {
    case resumeDraft
    case discardDraft
    case createFromServer
}

struct LayoutDraftConflict: Equatable, Sendable {
    let draft: LayoutDraft
    let serverSnapshot: LayoutSnapshot
}

enum LayoutEditorOpenResult {
    case created(LayoutEditorDocument)
    case resumed(LayoutEditorDocument)
    case conflict(LayoutDraftConflict)
}

enum LayoutEditorError: LocalizedError, Equatable {
    case administratorRequired
    case serverLayoutUnavailable
    case discardConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .administratorRequired:
            return "L’éditeur de réseau nécessite le rôle administrateur."
        case .serverLayoutUnavailable:
            return "Le layout publié n’est pas disponible."
        case .discardConfirmationRequired:
            return "Confirmez l’abandon des modifications locales."
        }
    }
}

@MainActor
final class LayoutEditorDocument: ObservableObject {
    @Published private(set) var topology: TopologyDefinition
    @Published private(set) var presentation: LayoutPresentationDefinition
    @Published private(set) var isDirty: Bool
    @Published private(set) var lastLocalSaveDate: Date?
    @Published private(set) var serverState: LayoutEditorServerState
    @Published private(set) var validationState: LayoutEditorValidationState = .notValidated

    let serverIdentity: String
    let baseTopologyRevision: String
    let basePresentationRevision: String

    private let draftStore: any LayoutDraftStoring
    private let autosaveDelayNanoseconds: UInt64
    private var autosaveTask: Task<Void, Never>?

    init(
        serverIdentity: String,
        snapshot: LayoutSnapshot,
        draftStore: any LayoutDraftStoring,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.serverIdentity = serverIdentity
        self.topology = snapshot.topology
        self.presentation = snapshot.presentation
        self.baseTopologyRevision = snapshot.topology.revision
        self.basePresentationRevision = snapshot.presentation.revision
        self.draftStore = draftStore
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
        self.isDirty = false
        self.serverState = .matchesBase
    }

    init(
        draft: LayoutDraft,
        draftStore: any LayoutDraftStoring,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.serverIdentity = draft.serverIdentity
        self.topology = draft.topology
        self.presentation = draft.presentation
        self.baseTopologyRevision = draft.baseTopologyRevision
        self.basePresentationRevision = draft.basePresentationRevision
        self.draftStore = draftStore
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
        self.isDirty = false
        self.lastLocalSaveDate = draft.savedAt
        self.serverState = .matchesBase
    }

    deinit {
        autosaveTask?.cancel()
    }

    static func open(
        serverIdentity: String,
        serverSnapshot: LayoutSnapshot,
        draftStore: any LayoutDraftStoring,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> LayoutEditorOpenResult {
        guard let draft = try await draftStore.load(
            serverIdentity: serverIdentity
        ) else {
            return .created(
                LayoutEditorDocument(
                    serverIdentity: serverIdentity,
                    snapshot: serverSnapshot,
                    draftStore: draftStore,
                    autosaveDelayNanoseconds: autosaveDelayNanoseconds
                )
            )
        }

        let revisionsMatch =
            draft.baseTopologyRevision == serverSnapshot.topology.revision &&
            draft.basePresentationRevision == serverSnapshot.presentation.revision

        guard revisionsMatch else {
            return .conflict(
                LayoutDraftConflict(
                    draft: draft,
                    serverSnapshot: serverSnapshot
                )
            )
        }

        return .resumed(
            LayoutEditorDocument(
                draft: draft,
                draftStore: draftStore,
                autosaveDelayNanoseconds: autosaveDelayNanoseconds
            )
        )
    }

    static func resolve(
        _ conflict: LayoutDraftConflict,
        resolution: LayoutDraftConflictResolution,
        draftStore: any LayoutDraftStoring,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> LayoutEditorDocument? {
        switch resolution {
        case .resumeDraft:
            let document = LayoutEditorDocument(
                draft: conflict.draft,
                draftStore: draftStore,
                autosaveDelayNanoseconds: autosaveDelayNanoseconds
            )
            document.serverState = .changed(
                topologyRevision: conflict.serverSnapshot.topology.revision,
                presentationRevision: conflict.serverSnapshot.presentation.revision
            )
            return document

        case .discardDraft:
            try await draftStore.delete(
                serverIdentity: conflict.draft.serverIdentity
            )
            return nil

        case .createFromServer:
            try await draftStore.delete(
                serverIdentity: conflict.draft.serverIdentity
            )
            return LayoutEditorDocument(
                serverIdentity: conflict.draft.serverIdentity,
                snapshot: conflict.serverSnapshot,
                draftStore: draftStore,
                autosaveDelayNanoseconds: autosaveDelayNanoseconds
            )
        }
    }

    func replaceTopology(_ topology: TopologyDefinition) {
        self.topology = topology
        didMutate()
    }

    func replacePresentation(_ presentation: LayoutPresentationDefinition) {
        self.presentation = presentation
        didMutate()
    }

    func updateServerRevisions(
        topologyRevision: String,
        presentationRevision: String
    ) {
        if topologyRevision == baseTopologyRevision,
           presentationRevision == basePresentationRevision {
            serverState = .matchesBase
        } else {
            serverState = .changed(
                topologyRevision: topologyRevision,
                presentationRevision: presentationRevision
            )
        }
    }

    func markServerUnavailable() {
        serverState = .unavailable
    }

    func setValidationState(_ state: LayoutEditorValidationState) {
        validationState = state
    }

    func saveNow() async throws {
        autosaveTask?.cancel()
        autosaveTask = nil
        try await performSave()
    }

    private func performSave() async throws {
        let savedAt = Date()
        try await draftStore.save(makeDraft(savedAt: savedAt))
        lastLocalSaveDate = savedAt
        isDirty = false
    }

    func prepareForValidationOrPublication() async throws {
        try await saveNow()
    }

    func discardLocalDraft() async throws {
        autosaveTask?.cancel()
        autosaveTask = nil
        try await draftStore.delete(serverIdentity: serverIdentity)
        isDirty = false
        lastLocalSaveDate = nil
    }

    private func didMutate() {
        isDirty = true
        validationState = .notValidated
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(
                    nanoseconds: self.autosaveDelayNanoseconds
                )
                guard !Task.isCancelled else { return }
                try await self.performSave()
            } catch is CancellationError {
                return
            } catch {
                // Keep the document dirty so a later explicit save can retry.
            }
        }
    }

    private func makeDraft(savedAt: Date) -> LayoutDraft {
        LayoutDraft(
            draftFormatVersion: LayoutDraft.currentFormatVersion,
            serverIdentity: serverIdentity,
            baseTopologyRevision: baseTopologyRevision,
            basePresentationRevision: basePresentationRevision,
            savedAt: savedAt,
            topology: topology,
            presentation: presentation
        )
    }
}
