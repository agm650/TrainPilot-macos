import SwiftUI
import TrainPilotCore
import UniformTypeIdentifiers

struct PadLibraryView: View {
    @ObservedObject var model: TrainPilotPadModel
    @State private var searchText = ""
    @State private var editedLocomotive: Locomotive?
    @State private var isCreating = false
    @State private var pendingDeletion: Locomotive?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: RollingStockArchiveDocument?
    @State private var exportFilename = "TrainPilot-rolling-stock.zip"

    var body: some View {
        NavigationStack {
            List {
                if filteredLocomotives.isEmpty {
                    Text(searchText.isEmpty ? "Aucune locomotive" : "Aucun résultat")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLocomotives) { locomotive in
                        NavigationLink(value: locomotive.id) {
                            LocomotiveRow(
                                locomotive: locomotive,
                                isActive: model.activeLocomotiveID == locomotive.id
                            )
                        }
                        .contextMenu {
                            if model.session?.isAdministrator == true {
                                Button("Modifier") {
                                    editedLocomotive = locomotive
                                }
                                Button("Supprimer", role: .destructive) {
                                    pendingDeletion = locomotive
                                }
                            }
                            Button("Sélectionner pour la conduite") {
                                selectForDriving(locomotive)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let locomotive = model.locomotives.first(where: { $0.id == id }) {
                    LocomotiveDetailView(
                        locomotive: locomotive,
                        isAdministrator: model.session?.isAdministrator == true,
                        isActive: model.activeLocomotiveID == locomotive.id,
                        onDrive: { selectForDriving(locomotive) },
                        onEdit: { editedLocomotive = locomotive },
                        onDelete: { pendingDeletion = locomotive }
                    )
                }
            }
        }
        .searchable(text: $searchText, prompt: "Nom ou adresse DCC")
        .navigationTitle("Bibliothèque")
        .toolbar {
            Button {
                Task {
                    guard let archive = await model.exportRollingStock() else { return }
                    exportDocument = RollingStockArchiveDocument(data: archive.data)
                    exportFilename = archive.suggestedFilename
                    isExporting = true
                }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }

            if model.session?.isAdministrator == true {
                Button {
                    isImporting = true
                } label: {
                    Label("Importer", systemImage: "square.and.arrow.down")
                }

                Button {
                    isCreating = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            Task { await importArchive(result) }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                model.errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .sheet(isPresented: $isCreating) {
            LocomotiveForm(title: "Nouvelle locomotive") { draft in
                Task {
                    if await model.saveLocomotive(id: nil, draft: draft) {
                        isCreating = false
                    }
                }
            } onCancel: {
                isCreating = false
            }
        }
        .sheet(item: $editedLocomotive) { locomotive in
            LocomotiveForm(
                title: "Modifier la locomotive",
                initialDraft: LocomotiveDraft(
                    name: locomotive.name,
                    dccAddress: locomotive.dccAddress,
                    addressKind: locomotive.addressKind,
                    speedSteps: locomotive.speedSteps,
                    manufacturer: locomotive.manufacturer ?? "",
                    model: locomotive.model ?? ""
                )
            ) { draft in
                Task {
                    if await model.saveLocomotive(id: locomotive.id, draft: draft) {
                        editedLocomotive = nil
                    }
                }
            } onCancel: {
                editedLocomotive = nil
            }
        }
        .confirmationDialog(
            "Supprimer cette locomotive ?",
            isPresented: deletionConfirmation,
            titleVisibility: .visible
        ) {
            if let locomotive = pendingDeletion {
                Button("Supprimer « \(locomotive.name) »", role: .destructive) {
                    Task { await model.deleteLocomotive(id: locomotive.id) }
                    pendingDeletion = nil
                }
            }
            Button("Annuler", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("Cette opération sera aussi soumise à l’autorisation du serveur.")
        }
    }

    private var filteredLocomotives: [Locomotive] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.locomotives }

        return model.locomotives.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                String($0.dccAddress).contains(query)
        }
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func selectForDriving(_ locomotive: Locomotive) {
        model.activeLocomotiveID = locomotive.id
        model.selectedSection = .driving
    }

    private func importArchive(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }
            _ = await model.importRollingStock(try Data(contentsOf: url))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct LocomotiveRow: View {
    let locomotive: Locomotive
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(locomotive.name)
                    .font(.headline)
                Text(locomotive.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Locomotive active")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LocomotiveDetailView: View {
    let locomotive: Locomotive
    let isAdministrator: Bool
    let isActive: Bool
    let onDrive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section("Identification") {
                LabeledContent("Nom", value: locomotive.name)
                if let manufacturer = locomotive.manufacturer {
                    LabeledContent("Constructeur", value: manufacturer)
                }
                if let model = locomotive.model {
                    LabeledContent("Modèle", value: model)
                }
            }
            Section("DCC") {
                LabeledContent("Adresse", value: String(locomotive.dccAddress))
                LabeledContent("Type", value: locomotive.addressKind)
                LabeledContent("Pas de vitesse", value: String(locomotive.speedSteps))
            }
            Section {
                Button(isActive ? "Ouvrir la conduite" : "Sélectionner pour la conduite", action: onDrive)
            }
            if isAdministrator {
                Section("Administration") {
                    Button("Modifier", action: onEdit)
                    Button("Supprimer", role: .destructive, action: onDelete)
                }
            }
        }
        .navigationTitle(locomotive.name)
    }
}

private struct RollingStockArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct LocomotiveForm: View {
    let title: String
    let onSave: (LocomotiveDraft) -> Void
    let onCancel: () -> Void

    @State private var draft: LocomotiveDraft

    init(
        title: String,
        initialDraft: LocomotiveDraft = LocomotiveDraft(),
        onSave: @escaping (LocomotiveDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identification") {
                    TextField("Nom", text: $draft.name)
                    TextField("Constructeur", text: $draft.manufacturer)
                    TextField("Modèle", text: $draft.model)
                }

                Section("DCC") {
                    Stepper(
                        "Adresse : \(draft.dccAddress)",
                        value: $draft.dccAddress,
                        in: 1...10_239
                    )
                    Picker("Type d’adresse", selection: $draft.addressKind) {
                        Text("Courte").tag("short")
                        Text("Longue").tag("long")
                    }
                    Picker("Pas de vitesse", selection: $draft.speedSteps) {
                        Text("14").tag(14)
                        Text("28").tag(28)
                        Text("128").tag(128)
                    }
                }

                if let validationMessage = draft.validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(draft)
                    }
                    .disabled(draft.validationMessage != nil)
                }
            }
        }
    }
}
