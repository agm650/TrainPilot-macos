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
        try read(data: Data(contentsOf: url))
    }

    func read(data: Data) throws -> Contents {
        let entries = try ZIPContainer.read(data)
        guard entries["manifest.json"] != nil else {
            throw LayoutArchiveError.missingEntry("manifest.json")
        }
        guard let data = entries["layout.json"],
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var topology = root["layout"] as? [String: Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }

        var presentation = (topology["presentation"] ?? root["presentation"]) as? [String: Any] ?? [:]
        for key in ["nodes", "trackSections", "turnoutTopologies", "blocks", "turnouts"] {
            if topology[key] == nil || topology[key] is NSNull { topology[key] = [] }
        }
        for key in ["nodes", "trackSections", "turnouts", "blocks"] {
            if presentation[key] == nil || presentation[key] is NSNull { presentation[key] = [] }
        }
        presentation["coordinateSystem"] = presentation["coordinateSystem"] ?? "layout-units"
        presentation["gridSpacing"] = presentation["gridSpacing"] ?? 20
        if var definitions = topology["turnouts"] as? [[String: Any]] {
            for index in definitions.indices {
                for key in ["endpoints", "positions"] {
                    if definitions[index][key] == nil || definitions[index][key] is NSNull {
                        definitions[index][key] = []
                    }
                }
                definitions[index]["name"] = definitions[index]["name"] ?? definitions[index]["id"]
                definitions[index]["kind"] = definitions[index]["kind"] ?? "custom"
            }
            topology["turnouts"] = definitions
        }
        let turnoutsData = try JSONSerialization.data(withJSONObject: topology["turnouts"] ?? [])
        let turnouts = try JSONDecoder().decode(
            [TurnoutDefinition].self,
            from: turnoutsData
        )
        topology.removeValue(forKey: "turnouts")
        topology["revision"] = topology["revision"] ?? "local"
        presentation["revision"] = presentation["revision"] ?? "local"
        // Older Studio archives used the same coordinates under a different name.
        if presentation["coordinateSystem"] as? String == "cartesian" {
            presentation["coordinateSystem"] = "layout-units"
        }

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
        if presentation["coordinateSystem"] as? String == "cartesian" {
            presentation["coordinateSystem"] = "layout-units"
        }
        topology["presentation"] = presentation

        let layoutData = try JSONSerialization.data(
            withJSONObject: [
                "layout": topology
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let manifestData = try LayoutArchiveFormat.manifestData()
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
    @Published private(set) var isPublishing = false

    var publication: (@MainActor (LayoutEditorDocument) async throws -> LayoutSnapshot?)?

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

    func publish() async {
        guard !isPublishing, let publication else { return }
        isPublishing = true
        message = "Validation serveur en cours…"
        defer { isPublishing = false }
        let document = controller.document
        do {
            guard let snapshot = try await publication(document) else {
                message = "Publication annulée."
                return
            }
            // Adopt the confirmed revisions so subsequent publications use the new base.
            var topology = snapshot.topology
            topology.occupancyProviders = document.topology.occupancyProviders
            topology.occupancySensorMappings = document.topology.occupancySensorMappings
            topology.feedbackMappings = document.topology.feedbackMappings
            replaceDocument(
                snapshot: LayoutSnapshot(topology: topology, presentation: snapshot.presentation),
                turnouts: document.turnoutDefinitions,
                name: documentName,
                origin: .server(ServerLayoutReference(serverIdentity: document.serverIdentity))
            )
            message = "Layout publié et rechargé depuis le serveur."
        } catch {
            if NetworkDiagnostics.isCancellation(error) {
                message = "Publication annulée."
            } else {
                message = error.localizedDescription
            }
        }
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
        let turnoutIssues = TurnoutValidator().validate(
            definitions: controller.document.turnoutDefinitions,
            topology: controller.document.topology,
            presentation: controller.document.presentation
        )
        if !turnoutIssues.isEmpty {
            message = "Brouillon incomplet : vérifiez les adresses DCC et les positions des appareils avant publication."
            return
        }
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
            coordinateSystem: "layout-units",
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
            LayoutTilePalette(controller: session.controller)
            Divider()
            HSplitView {
                LayoutStudioCanvas(controller: session.controller)
                    .frame(minWidth: 600, minHeight: 460)
                LayoutStudioInspector(
                    controller: session.controller,
                    message: session.message
                )
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 320)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .disabled(session.isPublishing)
    }
}

private struct LayoutStudioToolbar: View {
    @EnvironmentObject private var appModel: AppModel
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
            Button {
                controller.selectTool(.select)
            } label: {
                Image(systemName: "cursorarrow")
            }
            .help("Sélection : Maj-clic pour ajouter, glisser dans le vide pour encadrer")
            .tint(controller.tool == .select ? .accentColor : nil)

            Button {
                controller.selectTool(.pan)
            } label: {
                Image(systemName: "hand.draw")
            }
            .help("Déplacer le plan : cliquez et glissez")
            .tint(controller.tool == .pan ? .accentColor : nil)



            Button("Créer un canton") {
                do { try controller.createBlockFromSelection() }
                catch { session.message = error.localizedDescription }
            }
            .disabled(controller.selectedElements.isEmpty)
            Menu("Cantons") {
                ForEach(controller.document.topology.blocks) { block in
                    Button(block.name) { controller.select(.block(block.id)) }
                }
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
            Button {
                try? controller.deleteSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(controller.selection == nil)
            Spacer()
            Button(action: session.validateLocally) {
                Label("Valider", systemImage: "checkmark.circle")
            }
            Button("Publier") {
                Task { await session.publish() }
            }
            .disabled(session.publication == nil || !LayoutStudioAccessPolicy.canPublish(
                currentUser: appModel.currentUser,
                connectionState: appModel.connectionState
            ))
        }
        .buttonStyle(.bordered)
        .padding(8)
    }

}

private struct LayoutStudioCanvas: View {
    @ObservedObject var controller: LayoutEditorController
    @ObservedObject private var document: LayoutEditorDocument
    @AppStorage("layoutEditorSnapToGrid") private var snapToGrid = true
    @State private var selectionGestureActive = false
    @State private var movingSelection = false
    @State private var extendsSelection = false
    @State private var selectionBeforeGesture: Set<LayoutEditorSelection> = []
    @State private var selectionRectangle: (LayoutPoint, LayoutPoint)?

    init(controller: LayoutEditorController) {
        self.controller = controller
        document = controller.document
    }

    var body: some View {
        LayoutCanvas(
            topology: document.topology,
            presentation: document.presentation,
            mode: .editor(showHandles: controller.tool != .tile),
            locksToGrid: controller.tool == .tile,
            pansWithMouse: controller.tool == .pan,
            selectedElements: controller.selectedElements,
            selectionRectangle: selectionRectangle,
            onEditorGestureChanged: handleGestureChanged,
            onEditorGestureEnded: handleGesture
        )
        .onDisappear {
            controller.cancelDrag()
            selectionGestureActive = false
            movingSelection = false
            selectionRectangle = nil
        }
    }

    private func handleGestureChanged(
        start: LayoutPoint,
        end: LayoutPoint,
        transform: LayoutViewportTransform
    ) {
        guard controller.tool == .select else { return }
        if !selectionGestureActive {
            selectionGestureActive = true
            extendsSelection = NSEvent.modifierFlags.contains(.shift)
            selectionBeforeGesture = controller.selectedElements
            let hit = controller.element(at: start, tolerance: 8 / transform.zoom, includingNodes: false)
            if let hit {
                if extendsSelection {
                    var selected = controller.selectedElements
                    if selected.contains(hit) { selected.remove(hit) } else { selected.insert(hit) }
                    controller.selectElements(selected)
                } else if !controller.selectedElements.contains(hit) {
                    controller.select(hit)
                }
                movingSelection = !extendsSelection
                if movingSelection { controller.beginDrag() }
            } else {
                movingSelection = false
                if !extendsSelection { controller.select(nil) }
            }
        }
        if movingSelection {
            controller.updateSelectionDrag(
                delta: start.distance(to: end) > 3 / transform.zoom
                    ? LayoutPoint(x: end.x - start.x, y: end.y - start.y)
                    : LayoutPoint(x: 0, y: 0),
                snapEnabled: snapToGrid && !NSEvent.modifierFlags.contains(.option)
            )
        } else if start.distance(to: end) > 3 / transform.zoom,
                  controller.element(at: start, tolerance: 8 / transform.zoom, includingNodes: false) == nil {
            selectionRectangle = (start, end)
            let enclosed = controller.elements(inRectangleFrom: start, to: end)
            controller.selectElements(extendsSelection ? selectionBeforeGesture.union(enclosed) : enclosed)
        }
    }

    private func handleGesture(
        start: LayoutPoint,
        end: LayoutPoint,
        transform: LayoutViewportTransform
    ) {
        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
        switch controller.tool {
        case .select:
            handleGestureChanged(start: start, end: end, transform: transform)
            if movingSelection {
                controller.endDrag()
            } else if !extendsSelection && start.distance(to: end) <= 3 / transform.zoom {
                controller.selectElement(at: end, tolerance: 8 / transform.zoom)
            }
            selectionGestureActive = false
            movingSelection = false
            selectionRectangle = nil
        case .pan:
            break
        case .track:
            guard start.distance(to: end) >= 4 / transform.zoom else { return }
            controller.createTrack(
                from: start,
                to: end,
                transform: transform,
                snapEnabled: snapToGrid,
                optionKeyPressed: optionKeyPressed
            )
        case .turnout:
            try? controller.createTurnout(
                at: end,
                transform: transform,
                snapEnabled: snapToGrid,
                optionKeyPressed: optionKeyPressed
            )
        case .tile:
            do {
                try controller.placeTile(at: end)
            } catch {
                controller.tilePlacementMessage = error.localizedDescription
            }
        case .block:
            break
        }
    }
}

private struct LayoutStudioInspector: View {
    @ObservedObject var controller: LayoutEditorController
    @ObservedObject private var document: LayoutEditorDocument
    let message: String?

    init(controller: LayoutEditorController, message: String?) {
        self.controller = controller
        document = controller.document
        self.message = message
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            LayoutStudioDocumentInspector(
                revision: document.topology.revision,
                gridSpacing: document.presentation.gridSpacing
            )
            Divider()
            LayoutStudioSelectionInspector(description: selectionDescription)
            LayoutStudioSelectionControls(controller: controller)
            if case .block(let id) = controller.selection,
               let block = document.topology.blocks.first(where: { $0.id == id }) {
                LayoutBlockConfigurationView(controller: controller, document: document, block: block)
                    .id(id)
            }
            if controller.selectedElements.count == 1,
               case .turnout(let id) = controller.selection,
               let definition = document.turnoutDefinitions.first(where: { $0.id == id }) {
                LayoutTurnoutConfigurationView(controller: controller, definition: definition)
                    .id(id)
                    .padding(.vertical, 4)
            }
            Divider()
            LayoutStudioValidationInspector(message: message)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var selectionDescription: String {
        if controller.selectedElements.count > 1 {
            return "\(controller.selectedElements.count) éléments sélectionnés"
        }
        switch controller.inspectorState {
        case .noSelection: return "Aucune sélection"
        case .trackSection(let id): return "Voie \(id)"
        case .turnout(let id): return "Aiguillage \(id)"
        case .block(let id): return "Canton \(id)"
        case .node(let id): return "Nœud \(id)"
        }
    }
}

private struct LayoutStudioSelectionControls: View {
    @ObservedObject var controller: LayoutEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.selection {
            case .trackSection(let id):
                HStack {
                    Button("Droite") {
                        try? controller.convertTrackSegmentToLine(sectionID: id, segmentIndex: 0)
                    }
                    Button("Courbe") {
                        try? controller.convertTrackSegmentToCubic(sectionID: id, segmentIndex: 0)
                    }
                }
            case .turnout(let id):
                HStack {
                    Button("-90°") { rotateTurnout(id: id, delta: -90) }
                    Button("+90°") { rotateTurnout(id: id, delta: 90) }
                    Button("Miroir") { mirrorTurnout(id: id) }
                }
            case .block, .node, .none:
                EmptyView()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func rotateTurnout(id: String, delta: Double) {
        guard let turnout = controller.document.presentation.turnouts.first(where: {
            $0.turnoutId == id
        }) else { return }
        do {
            try controller.transformTurnout(id: id, rotationDegrees: turnout.rotationDegrees + delta)
        } catch {
            controller.tilePlacementMessage = error.localizedDescription
        }
    }

    private func mirrorTurnout(id: String) {
        guard let turnout = controller.document.presentation.turnouts.first(where: {
            $0.turnoutId == id
        }) else { return }
        do {
            try controller.transformTurnout(id: id, mirrored: !turnout.mirrored)
        } catch {
            controller.tilePlacementMessage = error.localizedDescription
        }
    }
}
