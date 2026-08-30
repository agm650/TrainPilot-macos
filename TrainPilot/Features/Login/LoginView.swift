import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        LoginFormView(preferences: appModel.preferences)
    }
}

private struct LoginFormView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject var preferences: AppPreferences

    @State private var password = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SNCFPalette.panel, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 44))
                        .foregroundColor(SNCFPalette.label)

                    Text("TrainPilot")
                        .font(.largeTitle.bold())
                        .foregroundColor(SNCFPalette.gauge)

                    Text("Poste de conduite macOS")
                        .foregroundColor(SNCFPalette.gauge.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Serveur")
                        .font(.caption.bold())
                        .foregroundColor(SNCFPalette.label)

                    TextField(
                        "http://192.168.0.60:8080",
                        text: $preferences.serverURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.black)
                    .environment(\.colorScheme, .light)

                    Text("Utilisateur")
                        .font(.caption.bold())
                        .foregroundColor(SNCFPalette.label)

                    TextField(
                        "Utilisateur",
                        text: $preferences.username
                    )
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.black)
                    .environment(\.colorScheme, .light)

                    Text("Mot de passe")
                        .font(.caption.bold())
                        .foregroundColor(SNCFPalette.label)

                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .foregroundColor(.black)
                        .environment(\.colorScheme, .light)
                        .onSubmit {
                            connect()
                        }

                    if let error = appModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(SNCFPalette.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        connect()
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text("Connexion")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canConnect)
                }
                .padding(22)
                .frame(width: 410)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(SNCFPalette.panelRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(SNCFPalette.metal, lineWidth: 1)
                        )
                )

                Text(
                    "Le mot de passe n'est pas enregistré. " +
                    "Le jeton de renouvellement est stocké dans le Trousseau macOS."
                )
                .font(.caption2)
                .foregroundColor(SNCFPalette.gauge.opacity(0.55))
                .frame(width: 420)
                .multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }

    private var isConnecting: Bool {
        appModel.connectionState == .connecting ||
        appModel.connectionState == .authenticating
    }

    private var canConnect: Bool {
        !preferences.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !preferences.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isConnecting
    }

    private func connect() {
        guard canConnect else {
            return
        }

        let username = preferences.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPassword = password

        Task {
            await appModel.login(
                username: username,
                password: currentPassword
            )

            if appModel.connectionState == .ready {
                password = ""
            }
        }
    }
}
