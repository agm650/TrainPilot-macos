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
    @Published var locomotives: [Locomotive] = []
    @Published var activeLocomotiveID: String?

    let preferences: any ServerPreferences

    private let keychain = KeychainStore()
    private var api: APIClient?

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
        guard let configuration = ServerConfiguration(serverAddress: serverAddress) else {
            errorMessage = "L’adresse du serveur est invalide."
            return
        }

        preferences.username = username
        preferences.serverAddress = serverAddress
        connectionState = .connecting
        errorMessage = nil

        do {
            let client = APIClient(baseURL: configuration.baseURL, keychain: keychain)
            let info = try await client.systemInfo()
            try await client.validateCompatibility(info)
            let tokenPair = try await client.login(
                username: username,
                password: password,
                clientID: preferences.clientID
            )
            api = client
            session = SessionIdentity(
                username: tokenPair.user.username,
                role: tokenPair.user.role
            )
            connectionState = .synchronizing
            async let locomotiveList = client.listLocomotives()
            async let status = client.stationStatus()
            locomotives = try await locomotiveList
            apply(try await status)
            connectionState = .ready
        } catch {
            api = nil
            session = nil
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        api = nil
        connectionState = .disconnected
        stationConnectivity = .unknown
        trackPower = .unknown
        session = nil
        locomotives = []
        activeLocomotiveID = nil
    }

    func saveLocomotive(id: String?, draft: LocomotiveDraft) async -> Bool {
        guard let api else { return false }
        let input = LocomotiveInput(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            dccAddress: draft.dccAddress,
            addressKind: draft.addressKind,
            speedSteps: draft.speedSteps,
            manufacturer: normalized(draft.manufacturer),
            model: normalized(draft.model)
        )

        do {
            if let id {
                _ = try await api.updateLocomotive(id: id, input: input)
            } else {
                _ = try await api.createLocomotive(input)
            }
            locomotives = try await api.listLocomotives()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteLocomotive(id: String) async {
        guard let api else { return }
        do {
            try await api.deleteLocomotive(id: id)
            locomotives = try await api.listLocomotives()
            if activeLocomotiveID == id {
                activeLocomotiveID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportRollingStock() async -> RollingStockExport? {
        guard let api else { return nil }
        do {
            return try await api.exportRollingStock()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importRollingStock(_ archive: Data) async -> Bool {
        guard let api, session?.isAdministrator == true else { return false }
        do {
            try await api.importRollingStock(archive: archive)
            locomotives = try await api.listLocomotives()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(_ status: StationStatus) {
        stationConnectivity = CommandStationConnectivity(
            rawValue: status.connectivity.rawValue
        ) ?? .unknown
        trackPower = TrackPowerStatus(rawValue: status.trackPower.rawValue) ?? .unknown
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
