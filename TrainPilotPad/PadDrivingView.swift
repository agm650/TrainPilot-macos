import SwiftUI
import TrainPilotCore

struct PadDrivingView: View {
    @ObservedObject var model: TrainPilotPadModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if let session = model.drivingSession {
                    DrivingControls(model: model, session: session)
                } else {
                    acquisition
                }

                emergencyStop
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Conduite")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Locomotive", selection: $model.activeLocomotiveID) {
                Text("Sélectionner…").tag(String?.none)
                ForEach(model.locomotives) { locomotive in
                    Text(locomotive.name).tag(Optional(locomotive.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(model.drivingSession != nil)

            if !model.canDrive {
                Label(
                    "Commandes indisponibles : la centrale doit être en ligne et la voie alimentée.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var acquisition: some View {
        if model.activeLocomotive == nil {
            VStack(spacing: 12) {
                Image(systemName: "train.side.front.car")
                    .font(.largeTitle)
                Text("Aucune locomotive sélectionnée")
                    .font(.headline)
                Text("Choisissez une locomotive avant d’acquérir son contrôle.")
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        } else {
            VStack(spacing: 12) {
                Button("Acquérir le contrôle") {
                    Task { await model.acquireActiveLocomotive() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canDrive)

                if model.takeoverLease != nil {
                    Button("Reprendre le contrôle de mon autre session") {
                        Task { await model.takeoverActiveLocomotive() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canDrive)
                }
            }
            .padding(32)
        }
    }

    private var emergencyStop: some View {
        Button {
            Task { await model.emergencyStop() }
        } label: {
            Label(
                model.stationEmergencyStop ? "ARRÊT D’URGENCE ACTIF" : "ARRÊT D’URGENCE",
                systemImage: "exclamationmark.octagon.fill"
            )
            .font(.title2.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(model.connectionState != .ready)
        .accessibilityHint("Arrête immédiatement toutes les locomotives via le serveur")
    }
}

private struct DrivingControls: View {
    @ObservedObject var model: TrainPilotPadModel
    @ObservedObject var session: DrivingSession

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.locomotive.name)
                        .font(.title.bold())
                    Text("Adresse DCC \(session.locomotive.dccAddress)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Libérer") {
                    Task { await model.releaseActiveLocomotive() }
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 10) {
                Text("\(session.requestedSpeed) %")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { Double(session.requestedSpeed) },
                        set: { model.setSpeed(Int($0.rounded())) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .disabled(!model.canDrive || session.selectorPosition == .neutral)
                .accessibilityLabel("Vitesse")
            }

            HStack(spacing: 12) {
                ForEach(DirectionSelectorPosition.allCases, id: \.self) { position in
                    Button(position.label) {
                        model.setSelector(position)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.selectorPosition == position ? .blue : .gray)
                    .disabled(
                        !model.canDrive ||
                            (position != .neutral && session.requestedSpeed != 0)
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sélecteur de sens")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 12) {
                ForEach(0...model.maximumFunctionNumber, id: \.self) { number in
                    Button {
                        Task { await model.toggleFunction(number) }
                    } label: {
                        Text("F\(number)")
                            .frame(minWidth: 52, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.functionStates[number] == true ? .blue : .gray)
                    .disabled(!model.canDrive)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
