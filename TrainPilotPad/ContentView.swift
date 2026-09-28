import SwiftUI

struct TrainPilotPadRootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "train.side.front.car")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("TrainPilot Cab")
                    .font(.largeTitle.bold())

                Text("Connectez-vous pour accéder à votre réseau ferroviaire.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                NavigationLink("Continuer") {
                    Text("Connexion")
                        .navigationTitle("Connexion")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("TrainPilot")
        }
    }
}
