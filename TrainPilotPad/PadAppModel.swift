import Combine
import Foundation
import TrainPilotCore

@MainActor
final class TrainPilotPadModel: ObservableObject {
    @Published var connectionState: ClientConnectionState = .disconnected
    @Published var stationConnectivity: CommandStationConnectivity = .unknown
    @Published var trackPower: TrackPowerStatus = .unknown
    @Published var session: SessionIdentity?
    @Published var selectedSection: PadSection? = .layout
    @Published var errorMessage: String?
    @Published var serverAddress: String

    let preferences: any ServerPreferences

    init(preferences: any ServerPreferences) {
        self.preferences = preferences
        serverAddress = preferences.serverAddress
    }

    var displayedTrackPower: TrackPowerStatus {
        stationConnectivity == .online ? trackPower : .unknown
    }

    var canDrive: Bool {
        connectionState == .ready &&
            stationConnectivity == .online &&
            displayedTrackPower == .on
    }

    func connect(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Renseignez votre nom d’utilisateur et votre mot de passe."
            return
        }

        preferences.username = username
        preferences.serverAddress = serverAddress
        connectionState = .connecting
        errorMessage = nil

        // The real API session is connected in the shared networking integration.
        connectionState = .ready
        stationConnectivity = .online
        trackPower = .unknown
        session = SessionIdentity(username: username, role: "driver")
    }

    func disconnect() {
        connectionState = .disconnected
        stationConnectivity = .unknown
        trackPower = .unknown
        session = nil
    }
}

enum PadSection: String, CaseIterable, Identifiable {
    case library
    case layout
    case driving
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .library: return "Bibliothèque"
        case .layout: return "Layout"
        case .driving: return "Conduite"
        case .settings: return "Réglages"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "train.side.front.car"
        case .layout: return "point.topleft.down.to.point.bottomright.curvepath"
        case .driving: return "gauge.with.dots.needle.67percent"
        case .settings: return "gearshape"
        }
    }
}
