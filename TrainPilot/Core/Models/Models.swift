import Foundation

enum DCCDirection: String, Codable, CaseIterable {
    case forward
    case reverse

    var shortLabel: String {
        switch self {
        case .forward: return "AV"
        case .reverse: return "AR"
        }
    }
}

enum DirectionSelectorPosition: String, CaseIterable {
    case forward
    case neutral
    case reverse

    var label: String {
        switch self {
        case .forward: return "AV"
        case .neutral: return "N"
        case .reverse: return "AR"
        }
    }
}

enum StationConnectivity: String, Codable {
    case online
    case degraded
    case offline
}

enum TrackPowerState: String, Codable {
    case on
    case off
    case unknown
}

struct Problem: Codable {
    let type: String
    let title: String
    let status: Int
    let detail: String?
    let code: String?
}

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let role: String
    let enabled: Bool
    let mustChangePassword: Bool
    let createdAt: Date
    let updatedAt: Date
    let lastLoginAt: Date?
}

struct Capabilities: Codable {
    let driver: String
    let trackPower: Bool
    let locomotiveControl: Bool
    let functions: Int
    let accessoryControl: Bool
    let feedback: Bool
}

struct SystemInfo: Codable {
    let serverVersion: String
    let apiVersion: String
    let minimumClientApiVersion: String
    let station: Capabilities
}

struct StationStatus: Codable {
    var connectivity: StationConnectivity
    var lastSeen: Date?
    var trackPower: TrackPowerState
    var emergencyStop: Bool
    var shortCircuit: Bool
    var programmingMode: Bool
    var mainCurrentMilliAmps: Int
    var programmingCurrentMilliAmps: Int
    var filteredMainCurrentMilliAmps: Int
    var temperatureCelsius: Int
    var supplyVoltageMilliVolts: Int
    var trackVoltageMilliVolts: Int
    var highTemperature: Bool
    var powerLost: Bool
    var externalShortCircuit: Bool
    var internalShortCircuit: Bool

    static var unknown: StationStatus {
        StationStatus(
            connectivity: .degraded,
            lastSeen: nil,
            trackPower: .unknown,
            emergencyStop: false,
            shortCircuit: false,
            programmingMode: false,
            mainCurrentMilliAmps: 0,
            programmingCurrentMilliAmps: 0,
            filteredMainCurrentMilliAmps: 0,
            temperatureCelsius: 0,
            supplyVoltageMilliVolts: 0,
            trackVoltageMilliVolts: 0,
            highTemperature: false,
            powerLost: false,
            externalShortCircuit: false,
            internalShortCircuit: false
        )
    }
}

struct Locomotive: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let dccAddress: Int
    let addressKind: String
    let speedSteps: Int
    let manufacturer: String?
    let model: String?

    var subtitle: String {
        let parts = [manufacturer, model].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "DCC \(dccAddress)" : "\(parts.joined(separator: " ")) · DCC \(dccAddress)"
    }
}

struct ControlLease: Codable, Identifiable {
    let id: String
    let locomotiveId: String
    let userId: String
    let sessionId: String
    var state: String
    let acquiredAt: Date
    var renewedAt: Date
    var expiresAt: Date
    var releaseAfter: Date?
    var releaseReason: String?
    let heartbeatMillis: Int
}

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    let sessionId: String
    let user: User
}

struct Block: Codable, Identifiable {
    let id: String
    let name: String
    var occupied: Bool
}

struct Turnout: Codable, Identifiable {
    let id: String
    let name: String
    let dccAddress: Int
    var desiredState: String
    var reportedState: String
}

struct Route: Codable, Identifiable {
    let id: String
    let name: String
    var state: String
    var reservedBySession: String?
}

struct ItemsResponse<T: Decodable>: Decodable {
    let items: [T]
}

struct LoginRequest: Encodable {
    let username: String
    let password: String
    let clientId: String
    let clientName: String
    let platform: String
}

struct ThrottleCommand: Encodable {
    let leaseId: String
    let speed: Int
    let direction: DCCDirection
}

struct FunctionCommand: Encodable {
    let leaseId: String
    let enabled: Bool
}

struct TrackPowerCommand: Encodable {
    let enabled: Bool
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

// MARK: - WebSocket

struct SystemSnapshot: Decodable {
    let type: String
    let sequence: UInt64
    let payload: SnapshotPayload
}

struct SnapshotPayload: Decodable {
    let capabilities: Capabilities?
    let stationStatus: StationStatus?
    let locomotives: [Locomotive]?
    let leases: [ControlLease]?
    let blocks: [Block]?
    let turnouts: [Turnout]?
    let routes: [Route]?

    private struct StationContainer: Decodable {
        let capabilities: Capabilities?
        let status: StationStatus?
    }

    private struct ArrayContainer<T: Decodable>: Decodable {
        let items: [T]
    }

    private enum CodingKeys: String, CodingKey {
        case station
        case stationStatus
        case locomotives
        case leases
        case controlLeases
        case blocks
        case turnouts
        case routes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var resolvedCapabilities: Capabilities?
        var resolvedStatus: StationStatus?

        if let direct = try? container.decode(Capabilities.self, forKey: .station) {
            resolvedCapabilities = direct
        } else if let nested = try? container.decode(StationContainer.self, forKey: .station) {
            resolvedCapabilities = nested.capabilities
            resolvedStatus = nested.status
        }

        if let directStatus = try? container.decode(StationStatus.self, forKey: .stationStatus) {
            resolvedStatus = directStatus
        }

        capabilities = resolvedCapabilities
        stationStatus = resolvedStatus
        locomotives = SnapshotPayload.decodeArray(Locomotive.self, from: container, key: .locomotives)
        blocks = SnapshotPayload.decodeArray(Block.self, from: container, key: .blocks)
        turnouts = SnapshotPayload.decodeArray(Turnout.self, from: container, key: .turnouts)
        routes = SnapshotPayload.decodeArray(Route.self, from: container, key: .routes)

        if let directLeases = SnapshotPayload.decodeArray(ControlLease.self, from: container, key: .leases) {
            leases = directLeases
        } else {
            leases = SnapshotPayload.decodeArray(ControlLease.self, from: container, key: .controlLeases)
        }
    }

    private static func decodeArray<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [T]? {
        if let direct = try? container.decode([T].self, forKey: key) {
            return direct
        }
        if let wrapped = try? container.decode(ArrayContainer<T>.self, forKey: key) {
            return wrapped.items
        }
        return nil
    }
}

struct ServerEvent {
    let type: String
    let sequence: UInt64
    let timestamp: Date?
    let payload: Data

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder.trainPilot.decode(T.self, from: payload)
    }
}

enum ServerMessage {
    case snapshot(SystemSnapshot)
    case event(ServerEvent)
}

struct StationStatusChangedPayload: Decodable {
    let connectivity: StationConnectivity
    let lastSeen: Date?
}

struct TrackPowerChangedPayload: Decodable {
    let enabled: Bool
}

struct EmergencyStopPayload: Decodable {
    let active: Bool
}

struct LocomotiveSpeedChangedPayload: Decodable {
    let locomotiveId: String
    let speed: Int
    let direction: DCCDirection
    let userId: String?
}

struct LocomotiveFunctionChangedPayload: Decodable {
    let locomotiveId: String
    let function: Int
    let enabled: Bool
}

struct LeaseExpiredPayload: Decodable {
    let leaseId: String
    let locomotiveId: String
    let reason: String
    let releaseAfter: Date?
}

extension JSONDecoder {
    static var trainPilot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}

struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let core = string.split(separator: "-", maxSplits: 1).first ?? Substring(string)
        let components = core.split(separator: ".")
        guard components.count >= 2,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = components.count > 2 ? (Int(components[2]) ?? 0) : 0
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
