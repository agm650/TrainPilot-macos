import SwiftUI
import TrainPilotCore

struct TrainPilotPadRootView: View {
    @StateObject private var model: TrainPilotPadModel

    init(preferences: any ServerPreferences) {
        _model = StateObject(wrappedValue: TrainPilotPadModel(preferences: preferences))
    }

    var body: some View {
        if model.session == nil {
            PadLoginView(model: model)
        } else {
            PadMainView(model: model)
        }
    }
}

private struct PadLoginView: View {
    @ObservedObject var model: TrainPilotPadModel
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Serveur") {
                    TextField("Adresse du serveur", text: $model.serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Compte") {
                    TextField("Nom d’utilisateur", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField("Mot de passe", text: $password)
                }

                Section {
                    Button("Connexion") {
                        Task {
                            await model.connect(username: username, password: password)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("TrainPilot Cab")
            .onAppear {
                username = model.preferences.username
            }
        }
    }

}

private struct PadMainView: View {
    @ObservedObject var model: TrainPilotPadModel

    var body: some View {
        VStack(spacing: 0) {
            PadStatusBar(
                connection: model.connectionState,
                station: model.stationConnectivity,
                trackPower: model.displayedTrackPower,
                username: model.session?.username ?? "",
                role: model.session?.role ?? ""
            )
            Divider()
            NavigationSplitView {
                List(PadSection.allCases, selection: $model.selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .navigationTitle("TrainPilot")
            } detail: {
                PadSectionView(model: model)
                    .toolbar {
                        Button("Déconnexion") {
                            model.disconnect()
                        }
                    }
            }
        }
    }
}

private struct PadStatusBar: View {
    let connection: ClientConnectionState
    let station: CommandStationConnectivity
    let trackPower: TrackPowerStatus
    let username: String
    let role: String

    var body: some View {
        HStack(spacing: 16) {
            StatusLabel(title: "Serveur", value: connection.rawValue)
            StatusLabel(title: "Centrale", value: station.rawValue)
            StatusLabel(title: "Voie", value: trackPower.rawValue.uppercased())
            Spacer()
            Label(username, systemImage: "person.crop.circle")
            Text(role)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .frame(minHeight: 48)
        .accessibilityElement(children: .contain)
    }
}

private struct StatusLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

private struct PadSectionView: View {
    @ObservedObject var model: TrainPilotPadModel

    var body: some View {
        switch model.selectedSection {
        case .library:
            PadLibraryView(model: model)
        case .layout:
            PadPlaceholderView(
                title: "Layout",
                message: "Le plan du réseau sera affiché ici en lecture seule.",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
        case .driving:
            PadPlaceholderView(
                title: "Conduite",
                message: model.canDrive
                    ? "Les commandes de conduite sont disponibles."
                    : "La conduite nécessite une centrale en ligne et une voie alimentée.",
                systemImage: "gauge.with.dots.needle.67percent"
            )
        case .settings:
            PadPlaceholderView(
                title: "Réglages",
                message: "Informations de session et configuration du serveur.",
                systemImage: "gearshape"
            )
        case nil:
            PadPlaceholderView(
                title: "Sélectionnez une section",
                message: "Choisissez une destination dans la barre latérale.",
                systemImage: "sidebar.left"
            )
        }
    }
}

private struct PadPlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(title)
    }
}
