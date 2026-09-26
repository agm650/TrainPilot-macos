import SwiftUI
import Foundation

struct SNCFClassicCabView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var keyboardController: KeyboardController?
    @State private var contentMode: CabContentMode = .network

    var body: some View {
        VStack(spacing: 0) {
            cabHeader
            Divider()

            if let session = appModel.driving.activeSession {
                CabSessionView(
                    session: session,
                    contentMode: $contentMode
                )
                .environmentObject(appModel)
            } else {
                emptyState
            }
        }
        .background(SNCFPalette.panel.ignoresSafeArea())
        .foregroundColor(SNCFPalette.gauge)
        .environment(\.colorScheme, .dark)
        .onAppear {
            guard !isRunningInXcodePreview else {
                return
            }

            let controller = KeyboardController(
                appModel: appModel
            )
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

    private var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo
            .environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var cabHeader: some View {
        HStack(spacing: 12) {
            Menu {
                if appModel.driving.sortedSessions.isEmpty {
                    Text("Aucune locomotive sous contrôle")
                } else {
                    ForEach(appModel.driving.sortedSessions) {
                        session in

                        Button {
                            appModel.driving.select(
                                locomotiveID:
                                    session.locomotive.id
                            )
                        } label: {
                            if appModel.driving
                                .activeLocomotiveID ==
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
                        appModel.driving.activeSession?
                            .locomotive.name
                        ?? "Locomotive"
                    )
                    .fontWeight(.semibold)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Picker(
                "Affichage",
                selection: $contentMode
            ) {
                ForEach(CabContentMode.allCases) { mode in
                    Text(mode.label)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            StatusPill(
                title: "SERVER",
                value: appModel.connectionState.label,
                color:
                    appModel.connectionState == .ready
                    ? SNCFPalette.green
                    : SNCFPalette.orange
            )
            .frame(width: 150)

            StatusPill(
                title: "CENTRALE",
                value:
                    appModel.stationStatus.connectivity
                        .rawValue
                        .uppercased(),
                color: connectivityColor
            )
            .frame(width: 160)

            Button {
                Task {
                    let enable =
                        displayedTrackPower != .on

                    await appModel.setTrackPower(enable)
                }
            } label: {
                StatusPill(
                    title: "VOIE",
                    value:
                        displayedTrackPower
                            .rawValue
                            .uppercased(),
                    color: displayedTrackPowerColor
                )
                .frame(width: 120)
            }
            .buttonStyle(.plain)
            .disabled(
                appModel.stationStatus.connectivity
                    != .online
                || appModel.systemInfo?
                    .station.trackPower != true
            )

            Button {
                Task {
                    if appModel.stationStatus
                        .emergencyStop {
                        await appModel
                            .clearEmergencyStop()
                    } else {
                        await appModel.emergencyStop()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            appModel.stationStatus
                                .emergencyStop
                            ? "arrow.clockwise.circle.fill"
                            : "exclamationmark.octagon.fill"
                    )

                    Text(
                        appModel.stationStatus
                            .emergencyStop
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
                            appModel.stationStatus
                                .emergencyStop
                            ? SNCFPalette.orange
                            : SNCFPalette.red
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                appModel.stationStatus.emergencyStop
                && appModel.stationStatus.connectivity
                    != .online
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(
                systemName: "train.side.front.car"
            )
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
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var displayedTrackPower: TrackPowerState {
        guard appModel.stationStatus.connectivity
            == .online else {
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
    @Binding var contentMode: CabContentMode

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 1200 &&
                geometry.size.height >= 800 {
                wideLayout(size: geometry.size)
            } else {
                compactLayout(size: geometry.size)
            }
        }
        .padding(18)
    }

    private func wideLayout(size: CGSize) -> some View {
        let networkHeight = min(
            max(size.height * 0.54, 360),
            520
        )

        return VStack(spacing: 14) {
            locomotivePlate

            HStack(
                alignment: .top,
                spacing: 16
            ) {
                SpeedGauge(
                    requested: session.requestedSpeed,
                    confirmed: session.confirmedSpeed
                )
                .frame(
                    width: 220,
                    height: 220
                )
                .frame(
                    height: networkHeight,
                    alignment: .center
                )

                CabContentArea(mode: contentMode)
                    .frame(
                        minWidth: 420,
                        maxWidth: .infinity,
                        minHeight: networkHeight,
                        maxHeight: networkHeight
                    )
                    .layoutPriority(1)

                VStack(spacing: 20) {
                    DirectionSelector(
                        position:
                            session.selectorPosition,
                        speed:
                            session.requestedSpeed,
                        disabled: controlsDisabled
                    ) { position in
                        Task {
                            await appModel
                                .selectDirection(
                                    locomotiveID:
                                        session
                                            .locomotive.id,
                                    position: position
                                )
                        }
                    }

                    Spacer(minLength: 8)

                    ThrottleWheel(
                        value:
                            session.requestedSpeed,
                        confirmedValue:
                            session.confirmedSpeed,
                        enabled: throttleEnabled,
                        onChange: { speed in
                            appModel
                                .setRequestedSpeed(
                                    locomotiveID:
                                        session
                                            .locomotive.id,
                                    speed: speed
                                )
                        },
                        onCommit: {
                            appModel.flushThrottle(
                                locomotiveID:
                                    session.locomotive.id
                            )
                        }
                    )
                    .frame(
                        width: 230,
                        height: 230
                    )

                    Spacer(minLength: 0)
                }
                .frame(
                    width: 250,
                    height: networkHeight,
                    alignment: .top
                )
            }
            .frame(height: networkHeight)

            FunctionPanel(
                session: session,
                functionCount: min(
                    appModel.systemInfo?
                        .station.functions ?? 13,
                    13
                ),
                columnCount: 8,
                disabled: controlsDisabled
            ) { function in
                Task {
                    await appModel.toggleFunction(
                        locomotiveID:
                            session.locomotive.id,
                        functionNumber: function
                    )
                }
            }
            .frame(height: 150)
        }
    }

    private func compactLayout(size: CGSize) -> some View {
        let networkHeight = min(
            max(size.height * 0.42, 240),
            360
        )

        let controlSize = min(
            max(size.height * 0.22, 150),
            190
        )

        let controlRowHeight = max(
            controlSize,
            174
        )

        return VStack(spacing: 12) {
            locomotivePlate

            CabContentArea(mode: contentMode)
                .frame(height: networkHeight)
                .layoutPriority(1)

            HStack(
                alignment: .center,
                spacing: 16
            ) {
                SpeedGauge(
                    requested: session.requestedSpeed,
                    confirmed: session.confirmedSpeed
                )
                .frame(
                    width: controlSize,
                    height: controlSize
                )

                Spacer(minLength: 0)

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
                .frame(
                    width: controlSize,
                    height: controlSize
                )
            }
            .frame(height: controlRowHeight)

            FunctionPanel(
                session: session,
                functionCount: min(
                    appModel.systemInfo?.station.functions ?? 13,
                    13
                ),
                columnCount: 6,
                disabled: controlsDisabled
            ) { function in
                Task {
                    await appModel.toggleFunction(
                        locomotiveID: session.locomotive.id,
                        functionNumber: function
                    )
                }
            }
            .frame(height: 130)
        }
    }

    private var locomotivePlate: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(session.locomotive.name)
                        .font(.title2.bold())

                    Text(session.locomotive.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 2
                ) {
                    Text("LEASE")
                        .font(.caption2.bold())
                        .foregroundColor(
                            SNCFPalette.label
                        )

                    Text(
                        session.lease.state
                            .uppercased()
                    )
                    .font(.caption.bold())
                    .foregroundColor(
                        session.lease.state == "active"
                        ? SNCFPalette.green
                        : SNCFPalette.orange
                    )
                }
            }

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
            .frame(
                height: 16,
                alignment: .leading
            )
        }
        .padding(12)
        .frame(minHeight: 82)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SNCFPalette.panelRaised)
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 10
                    )
                    .stroke(
                        SNCFPalette.metal,
                        lineWidth: 1
                    )
                )
        )
    }

    private var controlsDisabled: Bool {
        appModel.stationStatus.connectivity
            == .offline
        || appModel.stationStatus.emergencyStop
        || session.lease.state != "active"
    }

    private var throttleEnabled: Bool {
        !controlsDisabled
        && session.selectorPosition != .neutral
    }
}

// #if DEBUG
struct SNCFClassicCabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SNCFClassicCabView()
                .environmentObject(
                    PreviewData.cab(
                        selector: .neutral,
                        requestedSpeed: 0,
                        confirmedSpeed: 0,
                        direction: .forward
                    )
                )
                .frame(
                    width: 1440,
                    height: 900
                )
                .previewDisplayName(
                    "Cab — réseau"
                )

            SNCFClassicCabView()
                .environmentObject(
                    PreviewData.cab(
                        selector: .forward,
                        requestedSpeed: 50,
                        confirmedSpeed: 50,
                        direction: .forward
                    )
                )
                .frame(
                    width: 1440,
                    height: 900
                )
                .previewDisplayName(
                    "Cab — conduite"
                )
        }
    }
}
// #endif
