import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var appModel: AppModel

    @State private var editorPresentation: EditorPresentation?
    @State private var locomotiveToDelete: Locomotive?
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            Divider()

            if appModel.connectionState != .ready &&
                appModel.connectionState != .reconnecting {
                disconnectedView
            } else if appModel.locomotives.isEmpty {
                emptyLibraryView
            } else {
                List(appModel.locomotives) { locomotive in
                    LocomotiveRow(
                        locomotive: locomotive,
                        onEdit: {
                            editorPresentation = EditorPresentation(
                                locomotive: locomotive
                            )
                        },
                        onDelete: {
                            locomotiveToDelete = locomotive
                        }
                    )
                    .environmentObject(appModel)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(item: $editorPresentation) { presentation in
            LocomotiveEditorSheet(
                locomotive: presentation.locomotive
            )
            .environmentObject(appModel)
        }
        .alert(
            "Supprimer la locomotive ?",
            isPresented: deleteAlertBinding,
            presenting: locomotiveToDelete
        ) { locomotive in
            Button("Annuler", role: .cancel) {
                locomotiveToDelete = nil
            }

            Button("Supprimer", role: .destructive) {
                locomotiveToDelete = nil

                Task {
                    _ = await appModel.deleteLocomotive(
                        id: locomotive.id
                    )
                }
            }
        } message: { locomotive in
            Text(
                "\(locomotive.name) sera supprimée de la bibliothèque. " +
                "Le serveur refusera l'opération si cette locomotive est " +
                "encore utilisée ou référencée par l'historique de contrôle."
            )
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bibliothèque")
                    .font(.title2.bold())

                Text("\(appModel.locomotives.count) locomotive(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await appModel.refreshLocomotives()
                }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .disabled(appModel.connectionState != .ready)

            Button {
                exportLibrary()
            } label: {
                if exporting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Export…")
                    }
                } else {
                    Label(
                        "Exporter…",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
            .disabled(
                exporting ||
                appModel.connectionState != .ready
            )

            if appModel.isAdministrator {
                Button {
                    editorPresentation = EditorPresentation(
                        locomotive: nil
                    )
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.connectionState != .ready)
            }
        }
        .padding()
    }

    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Connectez d'abord TrainPilot au serveur.")

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "train.side.front.car")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("La bibliothèque est vide")
                .font(.title3.bold())

            if appModel.isAdministrator {
                Button("Ajouter une locomotive") {
                    editorPresentation = EditorPresentation(
                        locomotive: nil
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { locomotiveToDelete != nil },
            set: { newValue in
                if !newValue {
                    locomotiveToDelete = nil
                }
            }
        )
    }

    private func exportLibrary() {
        exporting = true

        Task {
            defer { exporting = false }

            guard let archive = await appModel.exportRollingStock() else {
                return
            }

            let panel = NSSavePanel()
            panel.title = "Exporter la bibliothèque TrainPilot"
            panel.nameFieldStringValue = archive.suggestedFilename
            panel.allowedContentTypes = [.zip]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK,
                  let url = panel.url else {
                return
            }

            do {
                try archive.data.write(
                    to: url,
                    options: .atomic
                )
            } catch {
                appModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let locomotive: Locomotive?
}

private struct LocomotiveRow: View {
    @EnvironmentObject var appModel: AppModel

    let locomotive: Locomotive
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tram.fill")
                .font(.title2)
                .frame(width: 34)
                .foregroundColor(SNCFPalette.label)

            VStack(alignment: .leading, spacing: 3) {
                Text(locomotive.name)
                    .font(.headline)

                Text(locomotive.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(
                    "Adresse \(locomotive.addressKind) · " +
                    "\(locomotive.speedSteps) pas"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            drivingControls

            if appModel.isAdministrator {
                Menu {
                    Button("Modifier…") {
                        onEdit()
                    }

                    Divider()

                    Button("Supprimer…", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var drivingControls: some View {
        if let session = appModel.driving.sessions[locomotive.id] {
            Text(session.lease.state.uppercased())
                .font(.caption.bold())
                .foregroundColor(
                    session.lease.state == "active"
                    ? SNCFPalette.green
                    : SNCFPalette.orange
                )

            Button("Conduire") {
                appModel.driving.select(
                    locomotiveID: locomotive.id
                )
            }

            Button("Libérer") {
                Task {
                    await appModel.release(
                        locomotiveID: locomotive.id
                    )
                }
            }
            .disabled(session.lease.state != "active")

        } else if let lease = appModel.leaseForLocomotive(
            locomotive.id
        ) {
            if appModel.isOwnLease(lease) {
                Text("LEASE DE CETTE SESSION")
                    .font(.caption.bold())
                    .foregroundColor(SNCFPalette.green)
            } else {
                Text("OCCUPÉE")
                    .font(.caption.bold())
                    .foregroundColor(SNCFPalette.orange)
            }
        } else {
            Button("Prendre le contrôle") {
                Task {
                    await appModel.acquire(locomotive)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct LocomotiveEditorSheet: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let locomotive: Locomotive?

    @State private var name: String
    @State private var manufacturer: String
    @State private var model: String
    @State private var dccAddressText: String
    @State private var addressKind: String
    @State private var speedSteps: Int
    @State private var saving = false

    init(locomotive: Locomotive?) {
        self.locomotive = locomotive

        _name = State(initialValue: locomotive?.name ?? "")
        _manufacturer = State(
            initialValue: locomotive?.manufacturer ?? ""
        )
        _model = State(initialValue: locomotive?.model ?? "")
        _dccAddressText = State(
            initialValue: locomotive.map {
                String($0.dccAddress)
            } ?? ""
        )
        _addressKind = State(
            initialValue: locomotive?.addressKind ?? "short"
        )
        _speedSteps = State(
            initialValue: locomotive?.speedSteps ?? 128
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(
                locomotive == nil
                ? "Ajouter une locomotive"
                : "Modifier la locomotive"
            )
            .font(.title2.bold())

            Form {
                Section("Identification") {
                    TextField("Nom", text: $name)
                    TextField(
                        "Fabricant (optionnel)",
                        text: $manufacturer
                    )
                    TextField(
                        "Modèle (optionnel)",
                        text: $model
                    )
                }

                Section("DCC") {
                    TextField(
                        "Adresse DCC",
                        text: $dccAddressText
                    )

                    Picker("Type d'adresse", selection: $addressKind) {
                        Text("Courte")
                            .tag("short")
                        Text("Longue")
                            .tag("long")
                    }
                    .pickerStyle(.segmented)

                    Picker("Pas de vitesse", selection: $speedSteps) {
                        Text("14")
                            .tag(14)
                        Text("28")
                            .tag(28)
                        Text("128")
                            .tag(128)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()

                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    if saving {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Enregistrement…")
                        }
                    } else {
                        Text("Enregistrer")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave || saving)
            }
        }
        .padding(22)
        .frame(width: 500)
    }

    private var parsedDCCAddress: Int? {
        Int(
            dccAddressText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        let address = parsedDCCAddress,
        (1...10239).contains(address),
        ["short", "long"].contains(addressKind),
        [14, 28, 128].contains(speedSteps) else {
            return false
        }

        return true
    }

    private var validationMessage: String? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedName.isEmpty {
            return "Le nom est obligatoire."
        }

        guard let address = parsedDCCAddress else {
            return "L'adresse DCC doit être un nombre entier."
        }

        if !(1...10239).contains(address) {
            return "L'adresse DCC doit être comprise entre 1 et 10239."
        }

        return nil
    }

    private func save() {
        guard canSave,
              let address = parsedDCCAddress else {
            return
        }

        saving = true

        let input = LocomotiveInput(
            name: name,
            dccAddress: address,
            addressKind: addressKind,
            speedSteps: speedSteps,
            manufacturer: manufacturer,
            model: model
        )

        Task {
            let result: Locomotive?

            if let locomotive {
                result = await appModel.updateLocomotive(
                    id: locomotive.id,
                    input: input
                )
            } else {
                result = await appModel.createLocomotive(input)
            }

            saving = false

            if result != nil {
                dismiss()
            }
        }
    }
}
