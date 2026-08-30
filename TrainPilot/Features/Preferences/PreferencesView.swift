import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        PreferencesForm(preferences: appModel.preferences)
            .padding(20)
    }
}

private struct PreferencesForm: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Connexion") {
                TextField(
                    "URL du serveur",
                    text: $preferences.serverURL
                )

                TextField(
                    "Utilisateur",
                    text: $preferences.username
                )

                HStack {
                    Text("Identifiant client")
                    Spacer()

                    Text(preferences.clientID)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Conduite") {
                Stepper(
                    "Cadence maximale throttle : " +
                    "\(preferences.throttleIntervalMilliseconds) ms",
                    value: $preferences.throttleIntervalMilliseconds,
                    in: 50...250,
                    step: 10
                )

                Text(
                    "N ou Espace ramène immédiatement la vitesse à 0 % " +
                    "tout en conservant le dernier sens DCC."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("Clavier") {
                shortcutRow("↑ / ↓", "+/- 1 %")
                shortcutRow("⇧↑ / ⇧↓", "+/- 10 %")
                shortcutRow("← / →", "AR / AV à 0 %")
                shortcutRow("Espace", "N / 0 % immédiat")
                shortcutRow("F1…F12", "Fonctions")
                shortcutRow("⌘1…⌘9", "Changer de locomotive")
                shortcutRow("⌘⌥E", "Arrêt d'urgence")
            }

            Section("Cabine") {
                HStack {
                    Text("Thème")
                    Spacer()
                    Text("SNCF Classic")
                        .foregroundColor(.secondary)
                }

                Text(
                    "Le MVP utilise une cabine composée de contrôles réutilisables. " +
                    "Les layouts personnalisables et l'éditeur utilisateur sont prévus " +
                    "pour une évolution ultérieure."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private func shortcutRow(
        _ key: String,
        _ action: String
    ) -> some View {
        HStack {
            Text(key)
                .font(.body.monospaced())
                .frame(width: 90, alignment: .leading)

            Text(action)
                .foregroundColor(.secondary)
        }
    }
}
