import SwiftUI
import TrainPilotCore

private enum PadCabPalette {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.07)
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.11)
    static let panelRaised = Color(red: 0.16, green: 0.17, blue: 0.16)
    static let metal = Color(red: 0.32, green: 0.33, blue: 0.31)
    static let label = Color(red: 0.92, green: 0.76, blue: 0.20)
    static let gauge = Color(red: 0.92, green: 0.92, blue: 0.85)
    static let action = Color(red: 0.10, green: 0.43, blue: 0.82)
    static let danger = Color(red: 0.84, green: 0.16, blue: 0.14)
}

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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                    PadLoginHeader()
                    PadLoginForm(
                        serverAddress: $model.serverAddress,
                        username: $username,
                        password: $password,
                        errorMessage: model.errorMessage,
                        connect: connect
                    )
                    PadLoginFooter()
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
            }
            .background(PadCabPalette.background)
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            username = model.preferences.username
        }
    }

    private func connect() {
        Task {
            await model.connect(username: username, password: password)
        }
    }
}

private struct PadLoginHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(PadCabPalette.label)
                .accessibilityHidden(true)
            Text("TrainPilot")
                .font(.largeTitle.bold())
                .foregroundStyle(PadCabPalette.gauge)
            Text("Poste de conduite iPad")
                .font(.headline)
                .foregroundStyle(PadCabPalette.metal)
        }
    }
}

private struct PadLoginForm: View {
    @Binding var serverAddress: String
    @Binding var username: String
    @Binding var password: String
    let errorMessage: String?
    let connect: () -> Void

    private var canConnect: Bool {
        !serverAddress.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PadLoginFieldLabel(title: "Serveur") {
                TextField("Adresse du serveur", text: $serverAddress)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            PadLoginFieldLabel(title: "Utilisateur") {
                TextField("Nom d’utilisateur", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            PadLoginFieldLabel(title: "Mot de passe") {
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                    .onSubmit(connect)
            }

            Button(action: connect) {
                Text("Connexion")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(PadCabPalette.action)
            .disabled(!canConnect)

            Text(errorMessage ?? " ")
                .font(.footnote)
                .foregroundStyle(PadCabPalette.danger)
                .opacity(errorMessage == nil ? 0 : 1)
                .accessibilityHidden(errorMessage == nil)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(PadCabPalette.panelRaised, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(PadCabPalette.metal.opacity(0.8), lineWidth: 1)
        }
    }
}

private struct PadLoginFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(PadCabPalette.label)
            content
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .foregroundStyle(.black)
                .background(PadCabPalette.gauge, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct PadLoginFooter: View {
    var body: some View {
        Text("Le mot de passe n’est pas enregistré. Le jeton de renouvellement est stocké dans le Trousseau iPadOS.")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PadCabPalette.metal)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
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
            PadLayoutView(model: model)
        case .driving:
            PadDrivingView(model: model)
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
