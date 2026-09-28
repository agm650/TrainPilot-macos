import SwiftUI
import TrainPilotCore

struct PadLayoutView: View {
    @ObservedObject var model: TrainPilotPadModel
    @State private var selectedTurnoutID: String?

    var body: some View {
        Group {
            if let topology = model.topology,
               let presentation = model.layoutPresentation {
                LayoutCanvas(
                    topology: topology,
                    presentation: presentation,
                    mode: .operationalReadOnly,
                    runtime: model.layoutRuntime,
                    onTurnoutSelected: { selectedTurnoutID = $0 }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.largeTitle)
                    Text("Layout indisponible")
                        .font(.headline)
                    Text("Le layout sera affiché après sa synchronisation avec le serveur.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Layout")
        .confirmationDialog(
            selectedTurnout?.name ?? "Aiguillage",
            isPresented: turnoutDialog,
            titleVisibility: .visible
        ) {
            if let turnout = selectedTurnout {
                ForEach(turnout.positions) { position in
                    Button(position.label ?? position.id) {
                        Task { await model.setTurnout(id: turnout.id, position: position.id) }
                        selectedTurnoutID = nil
                    }
                    .disabled(!model.canDrive || turnout.pending)
                }
            }
            Button("Annuler", role: .cancel) { selectedTurnoutID = nil }
        } message: {
            if !model.canDrive {
                Text("La centrale doit être en ligne et la voie alimentée.")
            } else if selectedTurnout?.pending == true {
                Text("Une commande est déjà en cours.")
            } else {
                Text("Choisissez la position à commander.")
            }
        }
    }

    private var selectedTurnout: Turnout? {
        guard let selectedTurnoutID else { return nil }
        return model.turnouts.first { $0.id == selectedTurnoutID }
    }

    private var turnoutDialog: Binding<Bool> {
        Binding(
            get: { selectedTurnoutID != nil },
            set: { if !$0 { selectedTurnoutID = nil } }
        )
    }
}
