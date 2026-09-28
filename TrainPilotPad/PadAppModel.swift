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
    @Published var drivingSession: DrivingSession?
    @Published var stationEmergencyStop = false
    @Published var topology: TopologyDefinition?
    @Published var layoutPresentation: LayoutPresentationDefinition?
    @Published var blocks: [Block] = []
    @Published var turnouts: [Turnout] = []
    @Published var maximumFunctionNumber = 12

    let preferences: any ServerPreferences

    private let keychain = KeychainStore()
    private var api: APIClient?
    private var eventClient: EventClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var throttleTask: Task<Void, Never>?
    private var baseURL: URL?
    private var currentUserID: String?
    private var currentSessionID: String?
    private var knownLeases: [ControlLease] = []

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
            displayedTrackPower == .on &&
            !stationEmergencyStop
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
            baseURL = configuration.baseURL
            currentUserID = tokenPair.user.id
            currentSessionID = tokenPair.sessionId
            session = SessionIdentity(
                username: tokenPair.user.username,
                role: tokenPair.user.role
            )
            connectionState = .synchronizing
            async let locomotiveList = client.listLocomotives()
            async let status = client.stationStatus()
            async let topologyDefinition = client.topology()
            async let presentationDefinition = client.layoutPresentation()
            async let blockList = client.listBlocks()
            async let turnoutList = client.listTurnouts()
            locomotives = try await locomotiveList
            apply(try await status)
            topology = try await topologyDefinition
            layoutPresentation = try await presentationDefinition
            blocks = try await blockList
            turnouts = try await turnoutList
            maximumFunctionNumber = max(0, info.station.maxFunctionNumber ?? 12)
            try await startEvents()
            connectionState = .ready
        } catch {
            api = nil
            session = nil
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        let client = api
        let events = eventClient
        let leaseID = drivingSession?.lease.id
        eventTask?.cancel()
        reconnectTask?.cancel()
        heartbeatTask?.cancel()
        throttleTask?.cancel()
        Task {
            if let leaseID { try? await client?.release(leaseID: leaseID) }
            await events?.disconnect()
            await client?.logout()
        }
        api = nil
        eventClient = nil
        connectionState = .disconnected
        stationConnectivity = .unknown
        trackPower = .unknown
        session = nil
        locomotives = []
        activeLocomotiveID = nil
        drivingSession = nil
        stationEmergencyStop = false
        topology = nil
        layoutPresentation = nil
        blocks = []
        turnouts = []
        knownLeases = []
        currentUserID = nil
        currentSessionID = nil
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

    var activeLocomotive: Locomotive? {
        guard let activeLocomotiveID else { return nil }
        return locomotives.first { $0.id == activeLocomotiveID }
    }

    var takeoverLease: ControlLease? {
        guard let locomotiveID = activeLocomotiveID,
              let currentUserID,
              let currentSessionID else { return nil }
        return knownLeases.first {
            $0.locomotiveId == locomotiveID &&
                $0.userId == currentUserID &&
                $0.sessionId != currentSessionID &&
                $0.state == "active"
        }
    }

    var layoutRuntime: TopologyRuntimeState {
        TopologyRuntimeState(blocks: blocks, turnouts: turnouts)
    }

    func acquireActiveLocomotive() async {
        guard let api, let locomotive = activeLocomotive, canDrive else { return }
        do {
            installSession(locomotive: locomotive, lease: try await api.acquire(locomotiveID: locomotive.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func takeoverActiveLocomotive() async {
        guard let api, let locomotive = activeLocomotive, let lease = takeoverLease else { return }
        do {
            installSession(locomotive: locomotive, lease: try await api.takeover(leaseID: lease.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func releaseActiveLocomotive() async {
        guard let api, let session = drivingSession else { return }
        do {
            try await api.release(leaseID: session.lease.id)
            heartbeatTask?.cancel()
            drivingSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setSelector(_ position: DirectionSelectorPosition) {
        guard let session = drivingSession else { return }
        if position == .neutral {
            session.requestedSpeed = 0
            session.selectorPosition = .neutral
            sendThrottle(speed: 0)
            return
        }
        guard session.requestedSpeed == 0 else { return }
        switch position {
        case .forward: session.direction = .forward
        case .reverse: session.direction = .reverse
        case .neutral: return
        }
        session.selectorPosition = position
        sendThrottle(speed: 0)
    }

    func setSpeed(_ speed: Int) {
        guard let session = drivingSession, session.selectorPosition != .neutral else { return }
        session.requestedSpeed = min(100, max(0, speed))
        sendThrottle(speed: session.requestedSpeed)
    }

    func toggleFunction(_ number: Int) async {
        guard let api, let session = drivingSession else { return }
        let enabled = !(session.functionStates[number] ?? false)
        do {
            try await api.setFunction(
                locomotiveID: session.locomotive.id,
                leaseID: session.lease.id,
                functionNumber: number,
                enabled: enabled
            )
            session.setFunction(number, enabled: enabled)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emergencyStop() async {
        guard let api else { return }
        do {
            try await api.emergencyStop()
            drivingSession?.requestedSpeed = 0
            drivingSession?.selectorPosition = .neutral
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setTurnout(id: String, position: String) async {
        guard let api, canDrive else { return }
        do {
            try await api.setTurnout(id: id, position: position)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installSession(locomotive: Locomotive, lease: ControlLease) {
        throttleTask?.cancel()
        heartbeatTask?.cancel()
        let session = DrivingSession(locomotive: locomotive, lease: lease)
        session.requestedSpeed = 0
        session.selectorPosition = .neutral
        drivingSession = session
        upsertLease(lease)
        startHeartbeat()
    }

    private func sendThrottle(speed: Int) {
        throttleTask?.cancel()
        guard let api, let session = drivingSession else { return }
        let locomotiveID = session.locomotive.id
        let leaseID = session.lease.id
        let direction = session.direction
        throttleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                try Task.checkCancellation()
                try await api.throttle(
                    locomotiveID: locomotiveID,
                    leaseID: leaseID,
                    speed: speed,
                    direction: direction
                )
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        guard let session = drivingSession else { return }
        let interval = max(500, session.lease.heartbeatMillis / 2)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
                    guard let self, let api = self.api, let active = self.drivingSession else { return }
                    active.lease = try await api.heartbeat(leaseID: active.lease.id)
                    self.upsertLease(active.lease)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self else { return }
                    self.drivingSession?.requestedSpeed = 0
                    self.drivingSession?.selectorPosition = .neutral
                    self.drivingSession = nil
                    self.errorMessage = "Le contrôle de la locomotive a été perdu : \(error.localizedDescription)"
                    return
                }
            }
        }
    }

    private func startEvents() async throws {
        guard let api, let baseURL else { return }
        let events = EventClient()
        eventClient = events
        let stream = try await events.connect(
            baseURL: baseURL,
            accessToken: try await api.accessTokenForWebSocket()
        )
        consume(stream)
    }

    private func consume(_ stream: AsyncStream<ServerMessage>) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await message in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(message)
            }
            guard !Task.isCancelled else { return }
            self?.connectionState = .reconnecting
            self?.drivingSession?.requestedSpeed = 0
            self?.drivingSession?.selectorPosition = .neutral
            self?.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            let delays: [UInt64] = [1, 2, 5, 10, 15]
            var attempt = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delays[min(attempt, delays.count - 1)] * 1_000_000_000)
                    guard let self else { return }
                    try await self.startEvents()
                    self.connectionState = .ready
                    return
                } catch is CancellationError {
                    return
                } catch {
                    attempt += 1
                }
            }
        }
    }

    private func handle(_ message: ServerMessage) async {
        switch message {
        case .snapshot(let snapshot):
            if let status = snapshot.payload.stationStatus { apply(status) }
            if let values = snapshot.payload.locomotives { locomotives = values }
            if let values = snapshot.payload.leases {
                knownLeases = values
                restoreOwnedSession(from: values)
            }
            if let values = snapshot.payload.blocks { blocks = values }
            if let values = snapshot.payload.turnouts { turnouts = values }
        case .event(let event):
            handle(event)
        }
    }

    private func handle(_ event: ServerEvent) {
        do {
            switch event.type {
            case "station.status.changed":
                let payload = try event.decodePayload(StationStatusChangedPayload.self)
                stationConnectivity = CommandStationConnectivity(rawValue: payload.connectivity.rawValue) ?? .unknown
            case "track.power.changed":
                let payload = try event.decodePayload(TrackPowerChangedPayload.self)
                trackPower = payload.enabled ? .on : .off
            case "track.emergency_stop":
                let payload = try event.decodePayload(EmergencyStopPayload.self)
                stationEmergencyStop = payload.active
                if payload.active {
                    drivingSession?.requestedSpeed = 0
                    drivingSession?.selectorPosition = .neutral
                }
            case "locomotive.speed.changed":
                let payload = try event.decodePayload(LocomotiveSpeedChangedPayload.self)
                if drivingSession?.locomotive.id == payload.locomotiveId {
                    drivingSession?.confirmedSpeed = payload.speed
                    drivingSession?.direction = payload.direction
                }
            case "locomotive.function.changed":
                let payload = try event.decodePayload(LocomotiveFunctionChangedPayload.self)
                if drivingSession?.locomotive.id == payload.locomotiveId {
                    drivingSession?.setFunction(payload.function, enabled: payload.enabled)
                }
            case "locomotive.control.acquired", "locomotive.control.transferred":
                let lease = try event.decodePayload(ControlLease.self)
                upsertLease(lease)
                restoreOwnedSession(from: [lease])
            case "locomotive.control.released":
                let lease = try event.decodePayload(ControlLease.self)
                upsertLease(lease)
                if drivingSession?.lease.id == lease.id {
                    heartbeatTask?.cancel()
                    drivingSession = nil
                }
            case "locomotive.control.expired":
                let payload = try event.decodePayload(LeaseExpiredPayload.self)
                if drivingSession?.lease.id == payload.leaseId {
                    heartbeatTask?.cancel()
                    drivingSession?.requestedSpeed = 0
                    drivingSession?.selectorPosition = .neutral
                    drivingSession = nil
                }
            case "block.occupancy.changed":
                let payload = try event.decodePayload(BlockOccupancyChangedPayload.self)
                if let index = blocks.firstIndex(where: { $0.id == payload.blockId }) {
                    blocks[index].occupied = payload.occupied
                    blocks[index].occupancy = BlockOccupancy(
                        state: payload.state,
                        occupant: payload.occupant,
                        updatedAt: payload.updatedAt
                    )
                }
            case "turnout.state.changed":
                let payload = try event.decodePayload(TurnoutStateChangedPayload.self)
                if let index = turnouts.firstIndex(where: { $0.id == payload.turnoutId }) {
                    turnouts[index].desiredPosition = payload.desiredPosition
                    turnouts[index].reportedPosition = payload.reportedPosition
                    turnouts[index].reportedStatus = payload.reportedStatus
                    turnouts[index].pending = payload.pending
                    turnouts[index].reportQuality = payload.reportQuality
                    turnouts[index].commandStatus = payload.commandStatus
                }
            default:
                break
            }
        } catch {
            // Unknown or newer payloads must not terminate event consumption.
        }
    }

    private func restoreOwnedSession(from leases: [ControlLease]) {
        guard drivingSession == nil,
              let currentSessionID,
              let lease = leases.first(where: { $0.sessionId == currentSessionID && $0.state == "active" }),
              let locomotive = locomotives.first(where: { $0.id == lease.locomotiveId }) else { return }
        activeLocomotiveID = locomotive.id
        installSession(locomotive: locomotive, lease: lease)
    }

    private func upsertLease(_ lease: ControlLease) {
        knownLeases.removeAll { $0.id == lease.id }
        knownLeases.append(lease)
    }

    private func apply(_ status: StationStatus) {
        stationConnectivity = CommandStationConnectivity(
            rawValue: status.connectivity.rawValue
        ) ?? .unknown
        trackPower = TrackPowerStatus(rawValue: status.trackPower.rawValue) ?? .unknown
        stationEmergencyStop = status.emergencyStop
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
