import SwiftUI

struct SNCFClassicCabView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var keyboardController: KeyboardController?

    var body: some View {
        VStack(spacing: 0) {
            cabHeader
            Divider()

            if let session = appModel.driving.activeSession {
                CabSessionView(session: session)
                    .environmentObject(appModel)
            } else {
                emptyState
            }
        }
        .background(SNCFPalette.panel.ignoresSafeArea())
        .foregroundColor(SNCFPalette.gauge)
        .environment(\.colorScheme, .dark)
        .onAppear {
            let controller = KeyboardController(appModel: appModel)
            controller.install()
            keyboardController = controller
        }
        .onDisappear {
            keyboardController?.uninstall()
            keyboardController = nil
        }
        .alert(
            "TrainPilot",
            isPresented: Binding(
                get: { appModel.errorMessage != nil },
                set: {
                    if !$0 {
                        appModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                appModel.errorMessage = nil
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }

    private var cabHeader: some View {
        HStack(spacing: 12) {
            Menu {
                if appModel.driving.sortedSessions.isEmpty {
                    Text("Aucune locomotive sous contrôle")
                } else {
                    ForEach(appModel.driving.sortedSessions) { session in
                        Button {
                            appModel.driving.select(
                                locomotiveID: session.locomotive.id
                            )
                        } label: {
                            if appModel.driving.activeLocomotiveID ==
                                session.locomotive.id {
                                Label(
                                    session.locomotive.name,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(session.locomotive.name)
                            }
                        }
                    }
                }

                Divider()

                Button("Bibliothèque…") {
                    WindowCoordinator.shared.showLibrary(
                        appModel: appModel
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "tram.fill")

                    Text(
                        appModel.driving.activeSession?.locomotive.name
                        ?? "Locomotive"
                    )
                    .fontWeight(.semibold)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            StatusPill(
                title: "SERVER",
                value: appModel.connectionState.label,
                color: appModel.connectionState == .ready
                    ? SNCFPalette.green
                    : SNCFPalette.orange
            )
            .frame(width: 150)

            StatusPill(
                title: "CENTRALE",
                value: appModel.stationStatus.connectivity
                    .rawValue
                    .uppercased(),
                color: connectivityColor
            )
            .frame(width: 160)

            Button {
                Task {
                    let enable = displayedTrackPower != .on
                    await appModel.setTrackPower(enable)
                }
            } label: {
                StatusPill(
                    title: "VOIE",
                    value: displayedTrackPower.rawValue.uppercased(),
                    color: displayedTrackPowerColor
                )
                .frame(width: 120)
            }
            .buttonStyle(.plain)
            .disabled(
                appModel.stationStatus.connectivity != .online ||
                appModel.systemInfo?.station.trackPower != true
            )

            Button {
                Task {
                    if appModel.stationStatus.emergencyStop {
                        await appModel.clearEmergencyStop()
                    } else {
                        await appModel.emergencyStop()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            appModel.stationStatus.emergencyStop
                            ? "arrow.clockwise.circle.fill"
                            : "exclamationmark.octagon.fill"
                    )

                    Text(
                        appModel.stationStatus.emergencyStop
                        ? "RÉARMER"
                        : "STOP"
                    )
                    .fontWeight(.heavy)
                }
                .frame(width: 130)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            appModel.stationStatus.emergencyStop
                            ? SNCFPalette.orange
                            : SNCFPalette.red
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                appModel.stationStatus.emergencyStop &&
                appModel.stationStatus.connectivity != .online
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "train.side.front.car")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Aucune locomotive sous contrôle")
                .font(.title2.bold())

            Text(
                "Ouvrez la bibliothèque et prenez le contrôle d'une locomotive."
            )
            .foregroundColor(.secondary)

            Button("Ouvrir la bibliothèque") {
                WindowCoordinator.shared.showLibrary(
                    appModel: appModel
                )
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayedTrackPower: TrackPowerState {
        guard appModel.stationStatus.connectivity == .online else {
            return .unknown
        }

        return appModel.stationStatus.trackPower
    }

    private var connectivityColor: Color {
        switch appModel.stationStatus.connectivity {
        case .online:
            return SNCFPalette.green
        case .degraded:
            return SNCFPalette.orange
        case .offline:
            return SNCFPalette.red
        }
    }

    private var displayedTrackPowerColor: Color {
        switch displayedTrackPower {
        case .on:
            return SNCFPalette.green
        case .off:
            return SNCFPalette.red
        case .unknown:
            return SNCFPalette.orange
        }
    }
}

private struct CabSessionView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject var session: DrivingSession

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 1000 {
                dashboardLayout
            } else {
                ScrollView {
                    narrowLayout
                }
            }
        }
        .padding(18)
    }

    // This layout is selected exclusively from the window width.
    // Runtime state changes (N/AV/AR, speed, confirmation, etc.)
    // therefore cannot cause the controls to be rearranged.
    private var dashboardLayout: some View {
        VStack(spacing: 14) {
            locomotivePlate

            HStack(alignment: .top, spacing: 16) {
                SpeedGauge(
                    requested: session.requestedSpeed,
                    confirmed: session.confirmedSpeed
                )
                .frame(width: 210, height: 210)

                DirectionSelector(
                    position: session.selectorPosition,
                    speed: session.requestedSpeed,
                    disabled: controlsDisabled
                ) { position in
                    Task {
                        await appModel.selectDirection(
                            locomotiveID: session.locomotive.id,
                            position: position
                        )
                    }
                }

                FunctionPanel(
                    session: session,
                    functionCount: min(
                        appModel.systemInfo?.station.functions ?? 13,
                        13
                    ),
                    columnCount: 8,
                    disabled: controlsDisabled
                ) { function in
                    Task {
                        await appModel.toggleFunction(
                            locomotiveID: session.locomotive.id,
                            functionNumber: function
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .layoutPriority(1)
            }
            .frame(height: 300, alignment: .top)

            ThrottleWheel(
                value: session.requestedSpeed,
                confirmedValue: session.confirmedSpeed,
                enabled: throttleEnabled,
                onChange: { speed in
                    appModel.setRequestedSpeed(
                        locomotiveID: session.locomotive.id,
                        speed: speed
                    )
                },
                onCommit: {
                    appModel.flushThrottle(
                        locomotiveID: session.locomotive.id
                    )
                }
            )
            .frame(width: 260, height: 260)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }

    private var narrowLayout: some View {
        VStack(spacing: 14) {
            locomotivePlate

            HStack(alignment: .top, spacing: 16) {
                SpeedGauge(
                    requested: session.requestedSpeed,
                    confirmed: session.confirmedSpeed
                )
                .frame(width: 180, height: 180)

                DirectionSelector(
                    position: session.selectorPosition,
                    speed: session.requestedSpeed,
                    disabled: controlsDisabled
                ) { position in
                    Task {
                        await appModel.selectDirection(
                            locomotiveID: session.locomotive.id,
                            position: position
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(height: 220, alignment: .top)

            FunctionPanel(
                session: session,
                functionCount: min(
                    appModel.systemInfo?.station.functions ?? 13,
                    13
                ),
                columnCount: 4,
                disabled: controlsDisabled
            ) { function in
                Task {
                    await appModel.toggleFunction(
                        locomotiveID: session.locomotive.id,
                        functionNumber: function
                    )
                }
            }
            .frame(height: 250)

            ThrottleWheel(
                value: session.requestedSpeed,
                confirmedValue: session.confirmedSpeed,
                enabled: throttleEnabled,
                onChange: { speed in
                    appModel.setRequestedSpeed(
                        locomotiveID: session.locomotive.id,
                        speed: speed
                    )
                },
                onCommit: {
                    appModel.flushThrottle(
                        locomotiveID: session.locomotive.id
                    )
                }
            )
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity)
        }
    }

    private var locomotivePlate: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.locomotive.name)
                        .font(.title2.bold())

                    Text(session.locomotive.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("LEASE")
                        .font(.caption2.bold())
                        .foregroundColor(SNCFPalette.label)

                    Text(session.lease.state.uppercased())
                        .font(.caption.bold())
                        .foregroundColor(
                            session.lease.state == "active"
                            ? SNCFPalette.green
                            : SNCFPalette.orange
                        )
                }
            }

            // Keep this row in the hierarchy at all times. Only its opacity
            // changes, so the locomotive plate never changes height.
            Text(
                "N : vitesse 0 %, sens DCC conservé \(session.direction.shortLabel)"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .opacity(
                session.selectorPosition == .neutral
                ? 1
                : 0
            )
            .frame(height: 16, alignment: .leading)
        }
        .padding(12)
        .frame(minHeight: 82)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SNCFPalette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            SNCFPalette.metal,
                            lineWidth: 1
                        )
                )
        )
    }

    private var controlsDisabled: Bool {
        appModel.stationStatus.connectivity == .offline ||
        appModel.stationStatus.emergencyStop ||
        session.lease.state != "active"
    }

    private var throttleEnabled: Bool {
        !controlsDisabled &&
        session.selectorPosition != .neutral
    }
}
