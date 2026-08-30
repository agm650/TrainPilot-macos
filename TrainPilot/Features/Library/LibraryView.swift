import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bibliothèque")
                        .font(.title2.bold())

                    Text("\(appModel.locomotives.count) locomotive(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task { await appModel.refreshLocomotives() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(appModel.connectionState != .ready)
            }
            .padding()

            Divider()

            if appModel.connectionState != .ready &&
                appModel.connectionState != .reconnecting {
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "network.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Connectez d'abord TrainPilot au serveur.")

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(appModel.locomotives) { locomotive in
                    LocomotiveRow(locomotive: locomotive)
                        .environmentObject(appModel)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

private struct LocomotiveRow: View {
    @EnvironmentObject var appModel: AppModel
    let locomotive: Locomotive

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
            }

            Spacer()

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

            } else if let lease = appModel.leaseForLocomotive(locomotive.id) {
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
        .padding(.vertical, 6)
    }
}
