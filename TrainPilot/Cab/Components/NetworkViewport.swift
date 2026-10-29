import SwiftUI

struct NetworkViewport: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let repository = model.layoutRepository {
            ObservedNetworkViewport(repository: repository)
        } else {
            NetworkViewportContent(snapshot: nil, availability: .unavailable)
        }
    }
}

// AppModel publishes repository replacement; this view observes its asynchronous contents.
private struct ObservedNetworkViewport: View {
    @ObservedObject var repository: LayoutRepository

    var body: some View {
        NetworkViewportContent(
            snapshot: repository.snapshot,
            availability: repository.availability
        )
    }
}

private struct NetworkViewportContent: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: LayoutSnapshot?
    let availability: LayoutAvailability
    @State private var selectedTurnoutID: String?
    @State private var sendingTurnouts: Set<String> = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot {
                LayoutCanvas(
                    topology: snapshot.topology,
                    presentation: snapshot.presentation,
                    mode: .operationalReadOnly,
                    runtime: TopologyRuntimeState(
                        blocks: model.blocks,
                        turnouts: model.turnouts
                    ),
                    onTurnoutSelected: handleTurnoutClick
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

    private func handleTurnoutClick(_ id: String) {
        guard let turnout = model.turnouts.first(where: { $0.id == id }) else { return }
        if canCommandTurnouts, let target = TopologyRuntimeState.toggleTarget(for: turnout) {
            send(turnout, position: target)
        } else {
            selectedTurnoutID = id
        }
    }

    private func send(_ turnout: Turnout, position: String) {
        guard canCommandTurnouts, !turnout.pending, turnout.commandStatus != .pending,
              !sendingTurnouts.contains(turnout.id) else { return }
        sendingTurnouts.insert(turnout.id)
        Task {
            await model.setTurnout(id: turnout.id, position: position)
            sendingTurnouts.remove(turnout.id)
        }
    }

    private var selectedTurnout: Turnout? {
        model.turnouts.first { $0.id == selectedTurnoutID }
    }

    private var canCommandTurnouts: Bool {
        model.connectionState == .ready &&
            availability == .ready &&
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
            Text("• cliquer sur un aiguillage")
                .foregroundColor(.secondary)
            if availability == .stale {
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
                    send(turnout, position: position.id)
                }
                .disabled(!canCommandTurnouts || turnout.pending || turnout.commandStatus == .pending || sendingTurnouts.contains(turnout.id))
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
            availability != .ready {
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
