import Foundation

public enum ClientConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case synchronizing
    case ready
    case reconnecting
    case failed
}

public enum CommandStationConnectivity: String, Equatable, Sendable {
    case online
    case degraded
    case offline
    case unknown
}

public enum TrackPowerStatus: String, Equatable, Sendable {
    case on
    case off
    case unknown
}

public struct SessionIdentity: Equatable, Sendable {
    public let username: String
    public let role: String

    public init(username: String, role: String) {
        self.username = username
        self.role = role
    }

    public var isAdministrator: Bool {
        role == "administrator"
    }
}
