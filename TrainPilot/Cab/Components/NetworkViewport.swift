import SwiftUI

struct NetworkViewport: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTurnoutID: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot = model.layoutRepository?.snapshot {
                LayoutCanvas(
                    topology: snapshot.topology,
                    presentation: snapshot.presentation,
                    mode: .operationalReadOnly,
                    runtime: TopologyRuntimeState(
                        blocks: model.blocks,
                        turnouts: model.turnouts
                    ),
                    onTurnoutSelected: { selectedTurnoutID = $0 }
                )
            } else {
                unavailableState
            }

            viewportLabel
                .padding(12)
                .allowsHitTesting(false)

            if let turnout = selectedTurnout {
                turnoutPanel(turnout)
                    .padding(.top, 52)
                    .padding(.leading, 12)
            }
        }
        .background(Color.black.opacity(0.18))
        .frame(
            minWidth: 300,
            maxWidth: .infinity,
            minHeight: 180,
            maxHeight: .infinity
        )
    }

    private var selectedTurnout: Turnout? {
        model.turnouts.first { $0.id == selectedTurnoutID }
    }

    private var canCommandTurnouts: Bool {
        model.connectionState == .ready &&
            model.layoutRepository?.availability == .ready &&
            model.stationStatus.connectivity == .online &&
            model.systemInfo?.station.accessoryControl == true
    }

    private var unavailableState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title)
            Text("Plan du réseau indisponible")
                .font(.headline)
            Text("Le plan réapparaîtra après synchronisation avec le serveur.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewportLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            Text("PLAN DU RÉSEAU")
                .fontWeight(.bold)
            Text("• lecture seule")
                .foregroundColor(.secondary)
            if model.layoutRepository?.availability == .stale {
                Label("données anciennes", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption)
        .foregroundColor(SNCFPalette.gauge)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(SNCFPalette.panel.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(SNCFPalette.metal, lineWidth: 1)
        )
    }

    private func turnoutPanel(_ turnout: Turnout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(turnout.name)
                    .font(.headline)
                Spacer()
                Button {
                    selectedTurnoutID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }

            HStack(spacing: 12) {
                runtimeValue(
                    label: "Demandé",
                    value: turnout.desiredPosition.isEmpty
                        ? "inconnu"
                        : turnout.desiredPosition
                )
                runtimeValue(
                    label: "Confirmé",
                    value: turnout.reportedPosition.isEmpty
                        ? "inconnu"
                        : turnout.reportedPosition
                )
            }

            if turnout.pending {
                Label("Transition en cours", systemImage: "clock.arrow.circlepath")
                    .foregroundColor(.yellow)
            } else if turnout.reportedStatus == .invalid {
                Label("Position physique incohérente", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            } else if turnout.reportedStatus == .unknown {
                Label("Position non confirmée", systemImage: "questionmark.circle")
                    .foregroundColor(.secondary)
            }

            Divider()

            ForEach(turnout.positions) { position in
                Button(position.label ?? position.id) {
                    Task {
                        await model.setTurnout(
                            id: turnout.id,
                            position: position.id
                        )
                    }
                }
                .disabled(!canCommandTurnouts || turnout.pending)
            }

            if !canCommandTurnouts {
                Text(commandUnavailableReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(SNCFPalette.metal, lineWidth: 1)
        )
    }

    private var commandUnavailableReason: String {
        if model.connectionState != .ready ||
            model.layoutRepository?.availability != .ready {
            return "Commande indisponible : serveur hors ligne"
        }
        if model.stationStatus.connectivity != .online {
            return "Commande indisponible : centrale hors ligne"
        }
        return "Commande d’aiguillage non prise en charge"
    }

    private func runtimeValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}
