import Foundation

public struct ServerConfiguration: Equatable, Sendable {
    public static let defaultAddress = "http://127.0.0.1:8080"

    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public init?(serverAddress: String) {
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressWithScheme = trimmedAddress.contains("://")
            ? trimmedAddress
            : "http://\(trimmedAddress)"

        guard let url = URL(string: addressWithScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        self.init(baseURL: url)
    }

    public var webSocketURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = baseURL.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.path = "/api/v1/events"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

public protocol ServerPreferences: AnyObject {
    var serverAddress: String { get set }
    var username: String { get set }
    var clientID: String { get }
}

public final class UserDefaultsServerPreferences: ServerPreferences {
    private enum Key {
        static let serverAddress = "serverAddress"
        static let username = "username"
        static let clientID = "clientID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.string(forKey: Key.clientID) == nil {
            defaults.set(UUID().uuidString, forKey: Key.clientID)
        }
    }

    public var serverAddress: String {
        get { defaults.string(forKey: Key.serverAddress) ?? "http://127.0.0.1:8080" }
        set { defaults.set(newValue, forKey: Key.serverAddress) }
    }

    public var username: String {
        get { defaults.string(forKey: Key.username) ?? "" }
        set { defaults.set(newValue, forKey: Key.username) }
    }

    public var clientID: String {
        defaults.string(forKey: Key.clientID) ?? ""
    }
}
