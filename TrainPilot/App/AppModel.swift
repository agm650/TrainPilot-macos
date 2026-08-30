import Foundation
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case synchronizing
    case ready
    case reconnecting
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Déconnecté"
        case .connecting: return "Connexion"
        case .authenticating: return "Authentification"
        case .synchronizing: return "Synchronisation"
        case .ready: return "Connecté"
        case .reconnecting: return "Reconnexion"
        case .failed: return "Erreur"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var systemInfo: SystemInfo?
    @Published var stationStatus: StationStatus = .unknown
    @Published var locomotives: [Locomotive] = []
    @Published var knownLeases: [ControlLease] = []
    @Published var errorMessage: String?
    @Published var currentUser: User?

    let preferences: AppPreferences
    let driving = DrivingSessionManager()

    private let keychain = KeychainStore()
    private var api: APIClient?
    private var eventClient: EventClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var throttleTasks: [String: Task<Void, Never>] = [:]
    private var leaseHeartbeatTasks: [String: Task<Void, Never>] = [:]

    private var currentSessionID: String?
    private var isLoggingOut = false
    private var restoreAttempted = false

    init(preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
    }

    func restoreSessionIfPossible() async {
        guard !restoreAttempted else { return }
        restoreAttempted = true

        guard let refreshToken = keychain.read(account: "refresh-token"),
              let url = normalizedServerURL() else {
            return
        }

        do {
            connectionState = .connecting
            let client = APIClient(baseURL: url, keychain: keychain)
            api = client

            let info = try await client.systemInfo()
            try await client.validateCompatibility(info)
            systemInfo = info

            connectionState = .authenticating
            let pair = try await client.restore(refreshToken: refreshToken)
            currentSessionID = pair.sessionId
            currentUser = pair.user

            try await bootstrap()
        } catch {
            keychain.delete(account: "refresh-token")
            clearRuntimeState()
            connectionState = .disconnected
        }
    }

    func login(username: String, password: String) async {
        guard let url = normalizedServerURL() else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return
        }

        errorMessage = nil
        reconnectTask?.cancel()

        do {
            connectionState = .connecting

            let client = APIClient(baseURL: url, keychain: keychain)
            api = client

            let info = try await client.systemInfo()
            try await client.validateCompatibility(info)
            systemInfo = info

            connectionState = .authenticating
            let pair = try await client.login(
                username: username,
                password: password,
                clientID: preferences.clientID
            )

            preferences.username = username
            currentSessionID = pair.sessionId
            currentUser = pair.user

            try await bootstrap()
        } catch {
            if isExpectedCancellation(error) {
                return
            }

            connectionState = .failed(error.localizedDescription)
            presentError(error)
        }
    }

    func logout() async {
        isLoggingOut = true
        reconnectTask?.cancel()
        eventTask?.cancel()

        for session in driving.sortedSessions {
            try? await api?.release(leaseID: session.lease.id)
        }

        await eventClient?.disconnect()
        await api?.logout()

        cancelAllLeaseHeartbeats()
        throttleTasks.values.forEach { $0.cancel() }
        throttleTasks.removeAll()

        clearRuntimeState()
        connectionState = .disconnected
        isLoggingOut = false
    }

    func refreshLocomotives() async {
        guard let api else { return }

        do {
            locomotives = try await api.listLocomotives()
        } catch {
            presentError(error)
        }
    }

    func acquire(_ locomotive: Locomotive) async {
        guard let api else { return }

        do {
            let lease = try await api.acquire(locomotiveID: locomotive.id)
            upsertLease(lease)
            _ = driving.add(locomotive: locomotive, lease: lease)
            startLeaseHeartbeat(for: locomotive.id)
        } catch {
            presentError(error)
        }
    }

    func release(locomotiveID: String) async {
        guard let api, let session = driving.sessions[locomotiveID] else { return }

        do {
            session.requestedSpeed = 0
            session.selectorPosition = .neutral
            session.lease.state = "stopping"
            try await api.release(leaseID: session.lease.id)
        } catch {
            presentError(error)
        }
    }

    func setRequestedSpeed(
        locomotiveID: String,
        speed: Int,
        immediate: Bool = false
    ) {
        guard let session = driving.sessions[locomotiveID] else { return }

        let clamped = min(max(speed, 0), 100)

        if session.selectorPosition == .neutral, clamped > 0 {
            return
        }

        session.requestedSpeed = clamped

        // A new throttle request supersedes the previous pending/in-flight one.
        // Cancellation is an expected part of throttle coalescing and must not
        // be surfaced as an application error.
        throttleTasks[locomotiveID]?.cancel()

        if immediate || clamped == 0 {
            throttleTasks[locomotiveID] = Task { [weak self] in
                await self?.sendThrottle(locomotiveID: locomotiveID)
            }
            return
        }

        let delayMs = preferences.throttleIntervalMilliseconds

        throttleTasks[locomotiveID] = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(delayMs) * 1_000_000
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.sendThrottle(locomotiveID: locomotiveID)
        }
    }

    func flushThrottle(locomotiveID: String) {
        throttleTasks[locomotiveID]?.cancel()

        throttleTasks[locomotiveID] = Task { [weak self] in
            await self?.sendThrottle(locomotiveID: locomotiveID)
        }
    }

    func selectDirection(
        locomotiveID: String,
        position: DirectionSelectorPosition
    ) async {
        guard let session = driving.sessions[locomotiveID] else { return }

        switch position {
        case .neutral:
            session.selectorPosition = .neutral
            session.requestedSpeed = 0
            throttleTasks[locomotiveID]?.cancel()
            await sendThrottle(locomotiveID: locomotiveID)

        case .forward, .reverse:
            guard session.requestedSpeed == 0 else {
                errorMessage = "Le changement de sens est autorisé uniquement à 0 %."
                return
            }

            session.direction = position == .forward ? .forward : .reverse
            session.selectorPosition = position

            throttleTasks[locomotiveID]?.cancel()

            // Send 0 % so the DCC direction is explicit without moving.
            await sendThrottle(locomotiveID: locomotiveID)
        }
    }

    func toggleFunction(
        locomotiveID: String,
        functionNumber: Int
    ) async {
        guard let api, let session = driving.sessions[locomotiveID] else { return }

        let previous = session.functionStates[functionNumber] ?? false
        let next = !previous
        session.setFunction(functionNumber, enabled: next)

        do {
            try await api.setFunction(
                locomotiveID: locomotiveID,
                leaseID: session.lease.id,
                functionNumber: functionNumber,
                enabled: next
            )
        } catch {
            session.setFunction(functionNumber, enabled: previous)
            presentError(error)
        }
    }

    func setTrackPower(_ enabled: Bool) async {
        guard let api else { return }

        do {
            try await api.setTrackPower(enabled)
        } catch {
            presentError(error)
        }
    }

    func emergencyStop() async {
        guard let api else { return }

        do {
            try await api.emergencyStop()

            for session in driving.sessions.values {
                session.requestedSpeed = 0
                session.selectorPosition = .neutral
            }
        } catch {
            presentError(error)
        }
    }

    func leaseForLocomotive(_ locomotiveID: String) -> ControlLease? {
        knownLeases.first {
            $0.locomotiveId == locomotiveID && $0.state != "released"
        }
    }

    func isOwnLease(_ lease: ControlLease) -> Bool {
        lease.sessionId == currentSessionID
    }

    private func bootstrap() async throws {
        guard let api, let baseURL = normalizedServerURL() else {
            throw APIError.invalidServerURL
        }

        locomotives = try await api.listLocomotives()
        stationStatus = try await api.stationStatus()
        connectionState = .synchronizing

        let accessToken = try await api.accessTokenForWebSocket()
        let eventClient = EventClient()
        self.eventClient = eventClient

        let stream = try await eventClient.connect(
            baseURL: baseURL,
            accessToken: accessToken
        )

        startConsuming(stream)
        connectionState = .ready
    }

    private func startConsuming(_ stream: AsyncStream<ServerMessage>) {
        eventTask?.cancel()

        eventTask = Task { [weak self] in
            for await message in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(message)
            }

            guard let self,
                  !Task.isCancelled,
                  !self.isLoggingOut else {
                return
            }

            await self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() async {
        guard reconnectTask == nil || reconnectTask?.isCancelled == true else {
            return
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            let delays: [UInt64] = [1, 2, 5, 10, 15]
            var attempt = 0

            while !Task.isCancelled, !self.isLoggingOut {
                self.connectionState = .reconnecting

                let seconds = delays[min(attempt, delays.count - 1)]

                do {
                    try await Task.sleep(
                        nanoseconds: seconds * 1_000_000_000
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                do {
                    guard let api = self.api,
                          let baseURL = self.normalizedServerURL() else {
                        throw APIError.invalidServerURL
                    }

                    let accessToken = try await api.accessTokenForWebSocket()
                    let eventClient = EventClient()
                    self.eventClient = eventClient

                    let stream = try await eventClient.connect(
                        baseURL: baseURL,
                        accessToken: accessToken
                    )

                    self.connectionState = .ready
                    self.reconnectTask = nil
                    self.startConsuming(stream)
                    return
                } catch {
                    if self.isExpectedCancellation(error) {
                        return
                    }

                    self.errorMessage =
                        "Reconnexion : \(error.localizedDescription)"
                    attempt += 1
                }
            }
        }
    }

    private func handle(_ message: ServerMessage) async {
        switch message {
        case .snapshot(let snapshot):
            if let status = snapshot.payload.stationStatus {
                stationStatus = status
            }

            if let locos = snapshot.payload.locomotives {
                locomotives = locos
            }

            if let leases = snapshot.payload.leases {
                knownLeases = leases
                restoreOwnSessions(from: leases)
            }

        case .event(let event):
            await handle(event)
        }
    }

    private func handle(_ event: ServerEvent) async {
        do {
            switch event.type {
            case "station.status.changed":
                let payload = try event.decodePayload(
                    StationStatusChangedPayload.self
                )
                stationStatus.connectivity = payload.connectivity
                stationStatus.lastSeen = payload.lastSeen

            case "track.power.changed":
                let payload = try event.decodePayload(
                    TrackPowerChangedPayload.self
                )
                stationStatus.trackPower = payload.enabled ? .on : .off

            case "track.emergency_stop":
                let payload = try event.decodePayload(
                    EmergencyStopPayload.self
                )
                stationStatus.emergencyStop = payload.active

                if payload.active {
                    for session in driving.sessions.values {
                        session.requestedSpeed = 0
                        session.selectorPosition = .neutral
                    }
                }

            case "locomotive.speed.changed":
                let payload = try event.decodePayload(
                    LocomotiveSpeedChangedPayload.self
                )

                if let session = driving.sessions[payload.locomotiveId] {
                    session.confirmedSpeed = payload.speed
                    session.direction = payload.direction
                }

            case "locomotive.function.changed":
                let payload = try event.decodePayload(
                    LocomotiveFunctionChangedPayload.self
                )

                driving.sessions[payload.locomotiveId]?.setFunction(
                    payload.function,
                    enabled: payload.enabled
                )

            case "locomotive.control.acquired":
                let lease = try event.decodePayload(ControlLease.self)
                upsertLease(lease)

                if isOwnLease(lease),
                   let locomotive = locomotives.first(where: {
                       $0.id == lease.locomotiveId
                   }) {
                    _ = driving.add(
                        locomotive: locomotive,
                        lease: lease,
                        makeActive: false
                    )
                    startLeaseHeartbeat(for: locomotive.id)
                }

            case "locomotive.control.released":
                let lease = try event.decodePayload(ControlLease.self)
                upsertLease(lease)

                if isOwnLease(lease) {
                    stopLeaseHeartbeat(for: lease.locomotiveId)
                    driving.remove(locomotiveID: lease.locomotiveId)
                }

            case "locomotive.control.expired":
                let payload = try event.decodePayload(
                    LeaseExpiredPayload.self
                )

                if let session = driving.sessions[payload.locomotiveId],
                   session.lease.id == payload.leaseId {
                    session.lease.state = "stopping"
                    session.requestedSpeed = 0
                    session.selectorPosition = .neutral
                }

            case "locomotive.created",
                 "locomotive.updated",
                 "locomotive.deleted":
                await refreshLocomotives()

            default:
                break
            }
        } catch {
            // Unknown/newer payloads must never break the WebSocket stream.
        }
    }

    private func sendThrottle(locomotiveID: String) async {
        guard let api,
              let session = driving.sessions[locomotiveID] else {
            return
        }

        guard !Task.isCancelled else { return }

        session.commandInFlight = true
        defer { session.commandInFlight = false }

        do {
            try await api.throttle(
                locomotiveID: locomotiveID,
                leaseID: session.lease.id,
                speed: session.requestedSpeed,
                direction: session.direction
            )
        } catch {
            // URLSession normally reports URLError.cancelled when a previous
            // throttle task is superseded by a newer position of the wheel.
            // This is expected control-flow, not an error to show to the driver.
            presentError(error)
        }
    }

    private func startLeaseHeartbeat(for locomotiveID: String) {
        stopLeaseHeartbeat(for: locomotiveID)

        guard let session = driving.sessions[locomotiveID] else {
            return
        }

        let interval = max(500, session.lease.heartbeatMillis / 2)

        leaseHeartbeatTasks[locomotiveID] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(interval) * 1_000_000
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      let self else {
                    return
                }

                await self.renewLease(locomotiveID: locomotiveID)
            }
        }
    }

    private func renewLease(locomotiveID: String) async {
        guard let api,
              let session = driving.sessions[locomotiveID] else {
            return
        }

        do {
            let renewed = try await api.heartbeat(
                leaseID: session.lease.id
            )
            session.lease = renewed
            upsertLease(renewed)
        } catch {
            if isExpectedCancellation(error) {
                return
            }

            errorMessage =
                "Lease \(session.locomotive.name) : \(error.localizedDescription)"
        }
    }

    private func stopLeaseHeartbeat(for locomotiveID: String) {
        leaseHeartbeatTasks[locomotiveID]?.cancel()
        leaseHeartbeatTasks.removeValue(forKey: locomotiveID)
    }

    private func cancelAllLeaseHeartbeats() {
        leaseHeartbeatTasks.values.forEach { $0.cancel() }
        leaseHeartbeatTasks.removeAll()
    }

    private func upsertLease(_ lease: ControlLease) {
        if let index = knownLeases.firstIndex(where: {
            $0.id == lease.id
        }) {
            knownLeases[index] = lease
        } else {
            knownLeases.append(lease)
        }
    }

    private func restoreOwnSessions(from leases: [ControlLease]) {
        guard currentSessionID != nil else { return }

        for lease in leases
        where isOwnLease(lease) && lease.state == "active" {
            guard let locomotive = locomotives.first(where: {
                $0.id == lease.locomotiveId
            }) else {
                continue
            }

            _ = driving.add(
                locomotive: locomotive,
                lease: lease,
                makeActive: false
            )

            startLeaseHeartbeat(for: locomotive.id)
        }
    }

    private func normalizedServerURL() -> URL? {
        var value = preferences.serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !value.contains("://") {
            value = "http://\(value)"
        }

        guard let url = URL(string: value),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return nil
        }

        return url
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError,
           urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            nsError.code == NSUserCancelledError
    }

    private func presentError(_ error: Error) {
        guard !isExpectedCancellation(error) else {
            return
        }

        errorMessage = error.localizedDescription
    }

    private func clearRuntimeState() {
        eventTask?.cancel()
        eventTask = nil

        reconnectTask?.cancel()
        reconnectTask = nil

        eventClient = nil
        api = nil

        systemInfo = nil
        stationStatus = .unknown
        locomotives = []
        knownLeases = []
        currentUser = nil
        currentSessionID = nil

        driving.removeAll()
    }
    
    func clearEmergencyStop() async {
        guard stationStatus.connectivity == .online else {
            errorMessage = "Impossible de réarmer : la centrale est hors ligne."
            return
        }

        guard let api else { return }

        do {
            // Le protocole TrainPilot définit un power-on explicite
            // comme l'action de réarmement après un emergency stop.
            try await api.setTrackPower(true)

            // Ne pas modifier stationStatus.emergencyStop ici.
            // On attend l'événement WebSocket track.emergency_stop(active: false)
            // émis par le serveur.
        } catch {
            presentError(error)
        }
    }
}
