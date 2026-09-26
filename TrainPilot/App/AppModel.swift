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
    @Published private(set) var blocks: [Block] = []
    @Published private(set) var turnouts: [Turnout] = []
    @Published var errorMessage: String?
    @Published var currentUser: User?
    @Published private(set) var layoutRepository: LayoutRepository?
    @Published private(set) var layoutEditorDocument: LayoutEditorDocument?
    @Published private(set) var layoutDraftConflict: LayoutDraftConflict?

    let preferences: AppPreferences
    let driving = DrivingSessionManager()

    private let keychain = KeychainStore()
    private let layoutDraftStore: any LayoutDraftStoring
    private var api: APIClient?
    private var eventClient: EventClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var throttleTasks: [String: Task<Void, Never>] = [:]
    private var leaseHeartbeatTasks: [String: Task<Void, Never>] = [:]

    private var currentSessionID: String?
    private var isLoggingOut = false
    private var restoreAttempted = false

    init(
        preferences: AppPreferences = AppPreferences(),
        layoutDraftStore: any LayoutDraftStoring = LayoutDraftStore()
    ) {
        self.preferences = preferences
        self.layoutDraftStore = layoutDraftStore
    }

    var isAdministrator: Bool {
        currentUser?.role == "administrator"
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
            layoutRepository = LayoutRepository(dataSource: client)

            let info = try await client.systemInfo()
            try await client.validateCompatibility(info)
            systemInfo = info

            connectionState = .authenticating
            let pair = try await client.restore(
                refreshToken: refreshToken
            )
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
            layoutRepository = LayoutRepository(dataSource: client)

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

        try? await layoutEditorDocument?.saveNow()

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

    // MARK: - Layout editor draft

    func openLayoutEditorDocument() async {
        guard isAdministrator else {
            presentError(LayoutEditorError.administratorRequired)
            return
        }

        guard let snapshot = layoutRepository?.snapshot,
              let serverIdentity = normalizedServerURL()?.absoluteString else {
            presentError(LayoutEditorError.serverLayoutUnavailable)
            return
        }

        do {
            let result = try await LayoutEditorDocument.open(
                serverIdentity: serverIdentity,
                serverSnapshot: snapshot,
                draftStore: layoutDraftStore
            )

            switch result {
            case .created(let document), .resumed(let document):
                layoutEditorDocument = document
                layoutDraftConflict = nil
            case .conflict(let conflict):
                layoutDraftConflict = conflict
            }
        } catch {
            presentError(error)
        }
    }

    func resolveLayoutDraftConflict(
        _ resolution: LayoutDraftConflictResolution
    ) async {
        guard let conflict = layoutDraftConflict else { return }

        do {
            layoutEditorDocument = try await LayoutEditorDocument.resolve(
                conflict,
                resolution: resolution,
                draftStore: layoutDraftStore
            )
            layoutDraftConflict = nil
        } catch {
            presentError(error)
        }
    }

    func saveLayoutDraft() async {
        do {
            try await layoutEditorDocument?.saveNow()
        } catch {
            presentError(error)
        }
    }

    func reloadLayoutEditorFromServer(
        discardingChanges: Bool
    ) async throws {
        guard let current = layoutEditorDocument,
              let snapshot = layoutRepository?.snapshot else {
            throw LayoutEditorError.serverLayoutUnavailable
        }

        if current.isDirty && !discardingChanges {
            throw LayoutEditorError.discardConfirmationRequired
        }

        try await current.discardLocalDraft()
        layoutEditorDocument = LayoutEditorDocument(
            serverIdentity: current.serverIdentity,
            snapshot: snapshot,
            draftStore: layoutDraftStore
        )
    }

    func layoutPublicationSucceeded() async {
        do {
            try await layoutEditorDocument?.discardLocalDraft()
            layoutEditorDocument = nil
            layoutDraftConflict = nil
        } catch {
            presentError(error)
        }
    }

    // MARK: - Rolling stock library

    func refreshLocomotives() async {
        guard let api else { return }

        do {
            let values = try await api.listLocomotives()
            locomotives = sortedLocomotives(values)
        } catch {
            presentError(error)
        }
    }

    func createLocomotive(
        _ input: LocomotiveInput
    ) async -> Locomotive? {
        guard isAdministrator else {
            errorMessage = "Cette opération nécessite le rôle administrateur."
            return nil
        }

        guard let api else { return nil }

        do {
            let locomotive = try await api.createLocomotive(input)
            upsertLocomotive(locomotive)
            return locomotive
        } catch {
            presentError(error)
            return nil
        }
    }

    func updateLocomotive(
        id: String,
        input: LocomotiveInput
    ) async -> Locomotive? {
        guard isAdministrator else {
            errorMessage = "Cette opération nécessite le rôle administrateur."
            return nil
        }

        guard let api else { return nil }

        do {
            let locomotive = try await api.updateLocomotive(
                id: id,
                input: input
            )
            upsertLocomotive(locomotive)
            return locomotive
        } catch {
            presentError(error)
            return nil
        }
    }

    func deleteLocomotive(id: String) async -> Bool {
        guard isAdministrator else {
            errorMessage = "Cette opération nécessite le rôle administrateur."
            return false
        }

        guard let api else { return false }

        do {
            try await api.deleteLocomotive(id: id)
            locomotives.removeAll { $0.id == id }
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func exportRollingStock() async -> RollingStockExport? {
        guard let api else { return nil }

        do {
            return try await api.exportRollingStock()
        } catch {
            presentError(error)
            return nil
        }
    }

    // MARK: - Driving

    func acquire(_ locomotive: Locomotive) async {
        guard let api else { return }

        do {
            let lease = try await api.acquire(
                locomotiveID: locomotive.id
            )
            upsertLease(lease)
            _ = driving.add(
                locomotive: locomotive,
                lease: lease
            )
            startLeaseHeartbeat(for: locomotive.id)
        } catch {
            presentError(error)
        }
    }

    func release(locomotiveID: String) async {
        guard let api,
              let session = driving.sessions[locomotiveID] else {
            return
        }

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
        guard let session = driving.sessions[locomotiveID] else {
            return
        }

        let clamped = min(max(speed, 0), 100)

        if session.selectorPosition == .neutral,
           clamped > 0 {
            return
        }

        session.requestedSpeed = clamped
        throttleTasks[locomotiveID]?.cancel()

        if immediate || clamped == 0 {
            throttleTasks[locomotiveID] = Task { [weak self] in
                await self?.sendThrottle(
                    locomotiveID: locomotiveID
                )
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
            await self?.sendThrottle(
                locomotiveID: locomotiveID
            )
        }
    }

    func flushThrottle(locomotiveID: String) {
        throttleTasks[locomotiveID]?.cancel()

        throttleTasks[locomotiveID] = Task { [weak self] in
            await self?.sendThrottle(
                locomotiveID: locomotiveID
            )
        }
    }

    func selectDirection(
        locomotiveID: String,
        position: DirectionSelectorPosition
    ) async {
        guard let session = driving.sessions[locomotiveID] else {
            return
        }

        switch position {
        case .neutral:
            session.selectorPosition = .neutral
            session.requestedSpeed = 0
            throttleTasks[locomotiveID]?.cancel()
            await sendThrottle(locomotiveID: locomotiveID)

        case .forward, .reverse:
            guard session.requestedSpeed == 0 else {
                errorMessage =
                    "Le changement de sens est autorisé uniquement à 0 %."
                return
            }

            session.direction = position == .forward
                ? .forward
                : .reverse
            session.selectorPosition = position
            throttleTasks[locomotiveID]?.cancel()
            await sendThrottle(locomotiveID: locomotiveID)
        }
    }

    func toggleFunction(
        locomotiveID: String,
        functionNumber: Int
    ) async {
        guard let api,
              let session = driving.sessions[locomotiveID] else {
            return
        }

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
            session.setFunction(
                functionNumber,
                enabled: previous
            )
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

    func clearEmergencyStop() async {
        guard stationStatus.connectivity == .online else {
            errorMessage =
                "Impossible de réarmer : la centrale est hors ligne."
            return
        }

        guard let api else { return }

        do {
            // A successful explicit power-on clears the server-side
            // emergency-stop interlock. The UI waits for the WebSocket
            // track.emergency_stop(active:false) confirmation.
            try await api.setTrackPower(true)
        } catch {
            presentError(error)
        }
    }

    func setTurnout(id: String, position: String) async {
        guard stationStatus.connectivity == .online else {
            errorMessage = "Impossible de commander l’aiguillage : la centrale est hors ligne."
            return
        }
        guard systemInfo?.station.accessoryControl == true else {
            errorMessage = "La centrale ne prend pas en charge la commande d’aiguillages."
            return
        }
        guard let api else { return }

        do {
            try await api.setTurnout(id: id, position: position)
        } catch {
            presentError(error)
        }
    }

    func leaseForLocomotive(
        _ locomotiveID: String
    ) -> ControlLease? {
        knownLeases.first {
            $0.locomotiveId == locomotiveID &&
            $0.state != "released"
        }
    }

    func isOwnLease(_ lease: ControlLease) -> Bool {
        lease.sessionId == currentSessionID
    }

    // MARK: - Bootstrap / WebSocket

    private func bootstrap() async throws {
        guard let api,
              let baseURL = normalizedServerURL() else {
            throw APIError.invalidServerURL
        }

        locomotives = sortedLocomotives(
            try await api.listLocomotives()
        )
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

    private func startConsuming(
        _ stream: AsyncStream<ServerMessage>
    ) {
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
        guard reconnectTask == nil ||
                reconnectTask?.isCancelled == true else {
            return
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            let delays: [UInt64] = [1, 2, 5, 10, 15]
            var attempt = 0

            while !Task.isCancelled,
                  !self.isLoggingOut {
                self.connectionState = .reconnecting

                let seconds = delays[
                    min(attempt, delays.count - 1)
                ]

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

                    let accessToken = try await api
                        .accessTokenForWebSocket()
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
                locomotives = sortedLocomotives(locos)
            }

            if let leases = snapshot.payload.leases {
                knownLeases = leases
                restoreOwnSessions(from: leases)
            }

            if let blocks = snapshot.payload.blocks {
                self.blocks = blocks
            }
            if let turnouts = snapshot.payload.turnouts {
                self.turnouts = turnouts
            }

            if let topologyRevision = snapshot.payload.topologyRevision,
               let presentationRevision = snapshot.payload.layoutPresentationRevision {
                do {
                    try await layoutRepository?.refreshIfNeeded(
                        topologyRevision: topologyRevision,
                        presentationRevision: presentationRevision
                    )
                    layoutEditorDocument?.updateServerRevisions(
                        topologyRevision: topologyRevision,
                        presentationRevision: presentationRevision
                    )
                } catch {
                    layoutEditorDocument?.markServerUnavailable()
                }
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
                stationStatus.trackPower = payload.enabled
                    ? .on
                    : .off

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

                if let session = driving.sessions[
                    payload.locomotiveId
                ] {
                    session.confirmedSpeed = payload.speed
                    session.direction = payload.direction
                }

            case "locomotive.function.changed":
                let payload = try event.decodePayload(
                    LocomotiveFunctionChangedPayload.self
                )

                driving.sessions[payload.locomotiveId]?
                    .setFunction(
                        payload.function,
                        enabled: payload.enabled
                    )

            case "locomotive.control.acquired":
                let lease = try event.decodePayload(
                    ControlLease.self
                )
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
                let lease = try event.decodePayload(
                    ControlLease.self
                )
                upsertLease(lease)

                if isOwnLease(lease) {
                    stopLeaseHeartbeat(
                        for: lease.locomotiveId
                    )
                    driving.remove(
                        locomotiveID: lease.locomotiveId
                    )
                }

            case "locomotive.control.expired":
                let payload = try event.decodePayload(
                    LeaseExpiredPayload.self
                )

                if let session = driving.sessions[
                    payload.locomotiveId
                ], session.lease.id == payload.leaseId {
                    session.lease.state = "stopping"
                    session.requestedSpeed = 0
                    session.selectorPosition = .neutral
                }

            case "locomotive.created",
                 "locomotive.updated",
                 "locomotive.deleted",
                 "rolling-stock.imported":
                await refreshLocomotives()

            case "layout.imported":
                // The following snapshot confirms authoritative revisions.
                break

            case "block.occupancy.changed":
                let payload = try event.decodePayload(
                    BlockOccupancyChangedPayload.self
                )
                if let index = blocks.firstIndex(where: { $0.id == payload.blockId }) {
                    blocks[index].occupied = payload.occupied
                    blocks[index].occupancy = BlockOccupancy(
                        state: payload.state,
                        occupant: payload.occupant,
                        updatedAt: payload.updatedAt
                    )
                }

            case "turnout.state.changed":
                let payload = try event.decodePayload(
                    TurnoutStateChangedPayload.self
                )
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
            // Unknown/newer payloads must never break the WebSocket stream.
        }
    }

    // MARK: - Command / lease keepalive

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
            presentError(error)
        }
    }

    private func startLeaseHeartbeat(for locomotiveID: String) {
        stopLeaseHeartbeat(for: locomotiveID)

        guard let session = driving.sessions[locomotiveID] else {
            return
        }

        let interval = max(
            500,
            session.lease.heartbeatMillis / 2
        )

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

                await self.renewLease(
                    locomotiveID: locomotiveID
                )
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
                "Lease \(session.locomotive.name) : " +
                error.localizedDescription
        }
    }

    private func stopLeaseHeartbeat(for locomotiveID: String) {
        leaseHeartbeatTasks[locomotiveID]?.cancel()
        leaseHeartbeatTasks.removeValue(
            forKey: locomotiveID
        )
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

    private func restoreOwnSessions(
        from leases: [ControlLease]
    ) {
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

    // MARK: - Helpers

    private func sortedLocomotives(
        _ values: [Locomotive]
    ) -> [Locomotive] {
        values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) ==
                .orderedAscending
        }
    }

    private func upsertLocomotive(_ locomotive: Locomotive) {
        if let index = locomotives.firstIndex(where: {
            $0.id == locomotive.id
        }) {
            locomotives[index] = locomotive
        } else {
            locomotives.append(locomotive)
        }

        locomotives = sortedLocomotives(locomotives)
    }

    private func normalizedServerURL() -> URL? {
        var value = preferences.serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !value.contains("://") {
            value = "http://\(value)"
        }

        guard let url = URL(string: value),
              let scheme = url.scheme,
              ["http", "https"].contains(
                  scheme.lowercased()
              ),
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
        layoutRepository = nil
        layoutEditorDocument = nil
        layoutDraftConflict = nil

        systemInfo = nil
        stationStatus = .unknown
        locomotives = []
        knownLeases = []
        blocks = []
        turnouts = []
        currentUser = nil
        currentSessionID = nil

        driving.removeAll()
    }
}
