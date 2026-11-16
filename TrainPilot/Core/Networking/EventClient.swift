import Foundation

actor EventClient {
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var continuation: AsyncStream<ServerMessage>.Continuation?

    private var tracker = SequenceTracker()
    private var awaitingSnapshot = true
    private var lastPong = Date()

    func connect(baseURL: URL, accessToken: String) throws -> AsyncStream<ServerMessage> {
        disconnectInternal()

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidServerURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v1/events"
        components.query = nil
        components.fragment = nil

        guard let webSocketURL = components.url else {
            throw APIError.invalidServerURL
        }

        var request = URLRequest(url: webSocketURL)
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var streamContinuation: AsyncStream<ServerMessage>.Continuation!
        let stream = AsyncStream<ServerMessage> { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation

        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        tracker = SequenceTracker()
        awaitingSnapshot = true

        lastPong = Date()
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.checkConnection()
            }
        }

        return stream
    }

    func disconnect() {
        disconnectInternal()
    }

    private func disconnectInternal() {
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil

        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil

        continuation?.finish()
        continuation = nil
    }

    private func receiveLoop() async {
        guard let socket else { return }

        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data

                switch message {
                case .data(let value):
                    data = value
                case .string(let value):
                    guard let encoded = value.data(using: .utf8) else { continue }
                    data = encoded
                @unknown default:
                    continue
                }

                try await process(data)
            }
        } catch {
            disconnectInternal()
        }
    }

    private func process(_ data: Data) async throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        if type == "system.snapshot" {
            let snapshot = try JSONDecoder.trainPilot.decode(SystemSnapshot.self, from: data)
            tracker.reset(to: snapshot.sequence)
            awaitingSnapshot = false
            continuation?.yield(.snapshot(snapshot))
            return
        }

        guard !awaitingSnapshot,
              let number = object["sequence"] as? NSNumber else {
            return
        }

        let sequence = number.uint64Value

        switch tracker.evaluate(sequence) {
        case .duplicate:
            return

        case .gap:
            awaitingSnapshot = true
            continuation?.yield(.resynchronizing)
            await requestSnapshot(lastSequence: tracker.lastSequence)
            return

        case .accept:
            let payloadObject = object["payload"] ?? [:]
            let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)

            var timestamp: Date?
            if let timestampString = object["timestamp"] as? String {
                timestamp = EventClient.parseDate(timestampString)
            }

            continuation?.yield(
                .event(
                    ServerEvent(
                        type: type,
                        sequence: sequence,
                        timestamp: timestamp,
                        payload: payloadData
                    )
                )
            )
        }
    }

    private func requestSnapshot(lastSequence: UInt64?) async {
        var message: [String: Any] = ["type": "client.snapshot_request"]
        if let lastSequence {
            message["lastSequence"] = lastSequence
        }
        await sendJSONObject(message)
    }

    private func checkConnection() {
        guard let socket else { return }
        guard Date().timeIntervalSince(lastPong) < 20 else {
            disconnectInternal()
            return
        }
        socket.sendPing { [weak self] error in
            Task { await self?.receivedPong(success: error == nil) }
        }
        // Keep the watchdog running even if a socket write is suspended.
        Task { [weak self] in await self?.sendHeartbeat() }
    }

    private func receivedPong(success: Bool) {
        if success { lastPong = Date() } else { disconnectInternal() }
    }

    private func sendHeartbeat() async {
        await sendJSONObject(["type": "client.heartbeat"])
    }

    private func sendJSONObject(_ object: [String: Any]) async {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await socket.send(.string(string))
        } catch {
            disconnectInternal()
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
