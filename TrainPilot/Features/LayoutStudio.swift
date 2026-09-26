import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum LayoutStudioAccessPolicy {
    static func canOpen(currentUser: User?) -> Bool {
        currentUser == nil || currentUser?.role == "administrator"
    }

    static func canPublish(currentUser: User?, connectionState: ConnectionState) -> Bool {
        currentUser?.role == "administrator" && connectionState == .ready
    }
}

private struct LayoutStudioDocumentInspector: View {
    let revision: String
    let gridSpacing: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Document").font(.headline)
            HStack {
                Text("Révision")
                Spacer()
                Text(revision)
            }
            HStack {
                Text("Grille")
                Spacer()
                Text("\(Int(gridSpacing))")
            }
        }
    }
}

private struct LayoutStudioSelectionInspector: View {
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sélection").font(.headline)
            Text(description).foregroundColor(.secondary)
        }
    }
}

private struct LayoutStudioValidationInspector: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Validation").font(.headline)
            Text(message ?? "Non validé").foregroundColor(.secondary)
        }
    }
}

enum LayoutTransferPolicy {
    static func canImport(currentUser: User?, connectionState: ConnectionState) -> Bool {
        currentUser?.role == "administrator" && connectionState == .ready
    }

    static func canExport(currentUser: User?, connectionState: ConnectionState) -> Bool {
        currentUser != nil && connectionState == .ready
    }
}

struct LayoutStudioArchiveService {
    struct Contents {
        let snapshot: LayoutSnapshot
        let turnouts: [TurnoutDefinition]
    }

    func read(from url: URL) throws -> Contents {
        let entries = try ZIPContainer.read(Data(contentsOf: url))
        guard entries["manifest.json"] != nil else {
            throw LayoutArchiveError.missingEntry("manifest.json")
        }
        guard let data = entries["layout.json"],
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var topology = root["layout"] as? [String: Any],
              var presentation = root["presentation"] as? [String: Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }

        let turnoutsData = try JSONSerialization.data(
            withJSONObject: topology["turnouts"] ?? []
        )
        let turnouts = try JSONDecoder().decode(
            [TurnoutDefinition].self,
            from: turnoutsData
        )
        topology.removeValue(forKey: "turnouts")
        topology["revision"] = topology["revision"] ?? "local"
        presentation["revision"] = presentation["revision"] ?? "local"
        root["layout"] = topology
        root["presentation"] = presentation

        let decoder = JSONDecoder()
        let topologyData = try JSONSerialization.data(withJSONObject: topology)
        let presentationData = try JSONSerialization.data(withJSONObject: presentation)
        return Contents(
            snapshot: LayoutSnapshot(
                topology: try decoder.decode(TopologyDefinition.self, from: topologyData),
                presentation: try decoder.decode(
                    LayoutPresentationDefinition.self,
                    from: presentationData
                )
            ),
            turnouts: turnouts
        )
    }

    @MainActor
    func archive(
        for document: LayoutEditorDocument,
        filename: String
    ) throws -> LayoutArchive {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var topology = try dictionary(for: document.topology, encoder: encoder)
        topology.removeValue(forKey: "revision")
        topology["turnouts"] = try array(for: document.turnoutDefinitions, encoder: encoder)
        var presentation = try dictionary(for: document.presentation, encoder: encoder)
        presentation.removeValue(forKey: "revision")

        let layoutData = try JSONSerialization.data(
            withJSONObject: [
                "layout": topology,
                "presentation": presentation
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: ["formatVersion": 1],
            options: [.prettyPrinted, .sortedKeys]
        )
        return LayoutArchive(
            data: ZIPContainer.write([
                "layout.json": layoutData,
                "manifest.json": manifestData
            ]),
            suggestedFilename: filename
        )
    }

    private func dictionary<T: Encodable>(
        for value: T,
        encoder: JSONEncoder
    ) throws -> [String: Any] {
        guard let dictionary = try JSONSerialization.jsonObject(
            with: encoder.encode(value)
        ) as? [String: Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }
        return dictionary
    }

    private func array<T: Encodable>(
        for value: T,
        encoder: JSONEncoder
    ) throws -> [Any] {
        guard let array = try JSONSerialization.jsonObject(
            with: encoder.encode(value)
        ) as? [Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }
        return array
    }
}

@MainActor
final class LayoutStudioSession: ObservableObject {
    @Published private(set) var controller: LayoutEditorController
    @Published var documentName: String
    @Published var message: String?

    let canPublish: Bool

    private let archiveService = LayoutStudioArchiveService()
    private let draftStore: any LayoutDraftStoring

    init(
        snapshot: LayoutSnapshot? = nil,
        turnouts: [TurnoutDefinition] = [],
        canPublish: Bool,
        draftStore: any LayoutDraftStoring = LayoutDraftStore()
    ) {
        self.draftStore = draftStore
        self.canPublish = canPublish
        let origin: LayoutDocumentOrigin = snapshot == nil
            ? .newLocal
            : .server(ServerLayoutReference(serverIdentity: "current-server"))
        documentName = snapshot == nil ? "Nouveau réseau" : "Copie du layout publié"
        controller = LayoutEditorController(
            document: LayoutEditorDocument(
                serverIdentity: "local:\(UUID().uuidString)",
                snapshot: snapshot ?? Self.emptySnapshot,
                draftStore: draftStore,
                turnoutDefinitions: turnouts,
                origin: origin
            )
        )
    }

    func newDocument() {
        replaceDocument(
            snapshot: Self.emptySnapshot,
            turnouts: [],
            name: "Nouveau réseau",
            origin: .newLocal
        )
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.title = "Ouvrir un layout"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: "dcclayout") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let contents = try archiveService.read(from: url)
            replaceDocument(
                snapshot: contents.snapshot,
                turnouts: contents.turnouts,
                name: url.deletingPathExtension().lastPathComponent,
                origin: .localFile(url)
            )
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func saveDocument() {
        do {
            let archive = try archiveService.archive(
                for: controller.document,
                filename: "\(documentName).dcclayout"
            )
            if let url = try LayoutArchiveSaver().save(
                archive,
                title: "Enregistrer le layout"
            ) {
                documentName = url.deletingPathExtension().lastPathComponent
                Task { try? await controller.document.saveNow() }
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func validateLocally() {
        let trackIssues = LayoutTrackValidator().validate(
            topology: controller.document.topology,
            presentation: controller.document.presentation
        )
        let blockIssues = LayoutBlockValidator().validate(
            topology: controller.document.topology,
            presentation: controller.document.presentation
        )
        message = trackIssues.isEmpty && blockIssues.isEmpty
            ? "Validation locale réussie."
            : "La validation locale a détecté \(trackIssues.count + blockIssues.count) problème(s)."
    }

    private func replaceDocument(
        snapshot: LayoutSnapshot,
        turnouts: [TurnoutDefinition],
        name: String,
        origin: LayoutDocumentOrigin
    ) {
        controller = LayoutEditorController(
            document: LayoutEditorDocument(
                serverIdentity: "local:\(UUID().uuidString)",
                snapshot: snapshot,
                draftStore: draftStore,
                turnoutDefinitions: turnouts,
                origin: origin
            )
        )
        documentName = name
    }

    static let emptySnapshot = LayoutSnapshot(
        topology: TopologyDefinition(
            revision: "local",
            nodes: [],
            trackSections: [],
            turnoutTopologies: [],
            blocks: []
        ),
        presentation: LayoutPresentationDefinition(
            revision: "local",
            coordinateSystem: "cartesian",
            gridSpacing: 20,
            nodes: [],
            trackSections: [],
            turnouts: [],
            blocks: []
        )
    )
}

struct LayoutStudioView: View {
    @ObservedObject var session: LayoutStudioSession

    var body: some View {
        VStack(spacing: 0) {
            LayoutStudioToolbar(session: session)
            Divider()
            HSplitView {
                LayoutStudioCanvas(controller: session.controller)
                    .frame(minWidth: 600, minHeight: 460)
                LayoutStudioInspector(
                    document: session.controller.document,
                    selection: session.controller.inspectorState,
                    message: session.message
                )
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 320)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

private struct LayoutStudioToolbar: View {
    @ObservedObject var session: LayoutStudioSession
    @ObservedObject private var controller: LayoutEditorController

    init(session: LayoutStudioSession) {
        self.session = session
        controller = session.controller
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: session.newDocument) {
                Label("Nouveau", systemImage: "doc")
            }
            Button(action: session.openDocument) {
                Label("Ouvrir", systemImage: "folder")
            }
            Button(action: session.saveDocument) {
                Label("Enregistrer", systemImage: "square.and.arrow.down")
            }
            Divider().frame(height: 22)
            ForEach(LayoutEditorTool.allCases, id: \.self) { tool in
                Button {
                    controller.selectTool(tool)
                } label: {
                    Image(systemName: symbol(for: tool))
                }
                .help(label(for: tool))
                .buttonStyle(.bordered)
                .tint(controller.tool == tool ? .accentColor : nil)
            }
            Divider().frame(height: 22)
            Button(action: controller.undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!controller.canUndo)
            Button(action: controller.redo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!controller.canRedo)
            Spacer()
            Button(action: session.validateLocally) {
                Label("Valider", systemImage: "checkmark.circle")
            }
            Button("Publier") {}
                .disabled(!session.canPublish)
        }
        .buttonStyle(.bordered)
        .padding(8)
    }

    private func symbol(for tool: LayoutEditorTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .track: return "point.topleft.down.to.point.bottomright.curvepath"
        case .turnout: return "arrow.triangle.branch"
        case .block: return "rectangle.3.group"
        }
    }

    private func label(for tool: LayoutEditorTool) -> String {
        switch tool {
        case .select: return "Sélection"
        case .track: return "Voie"
        case .turnout: return "Aiguillage"
        case .block: return "Block"
        }
    }
}

private struct LayoutStudioCanvas: View {
    @ObservedObject var controller: LayoutEditorController
    @ObservedObject private var document: LayoutEditorDocument

    init(controller: LayoutEditorController) {
        self.controller = controller
        document = controller.document
    }

    var body: some View {
        LayoutCanvas(
            topology: document.topology,
            presentation: document.presentation,
            mode: .editor(showHandles: true)
        )
    }
}

private struct LayoutStudioInspector: View {
    @ObservedObject var document: LayoutEditorDocument
    let selection: LayoutInspectorState
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LayoutStudioDocumentInspector(
                revision: document.topology.revision,
                gridSpacing: document.presentation.gridSpacing
            )
            Divider()
            LayoutStudioSelectionInspector(description: selectionDescription)
            Divider()
            LayoutStudioValidationInspector(message: message)
            Spacer()
        }
        .padding()
    }

    private var selectionDescription: String {
        switch selection {
        case .noSelection: return "Aucune sélection"
        case .trackSection(let id): return "Voie \(id)"
        case .turnout(let id): return "Aiguillage \(id)"
        case .block(let id): return "Block \(id)"
        case .node(let id): return "Nœud \(id)"
        }
    }
}
