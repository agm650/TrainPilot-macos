import Foundation
import Combine

final class AppPreferences: ObservableObject {
    private enum Keys {
        static let serverURL = "serverURL"
        static let username = "username"
        static let clientID = "clientID"
        static let throttleIntervalMilliseconds = "throttleIntervalMilliseconds"
    }

    private let defaults: UserDefaults

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    @Published var throttleIntervalMilliseconds: Int {
        didSet {
            let clamped = min(max(throttleIntervalMilliseconds, 50), 250)
            if clamped != throttleIntervalMilliseconds {
                throttleIntervalMilliseconds = clamped
            } else {
                defaults.set(clamped, forKey: Keys.throttleIntervalMilliseconds)
            }
        }
    }

    let clientID: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverURL = defaults.string(forKey: Keys.serverURL) ?? "http://127.0.0.1:8080"
        self.username = defaults.string(forKey: Keys.username) ?? ""

        let storedInterval = defaults.integer(forKey: Keys.throttleIntervalMilliseconds)
        self.throttleIntervalMilliseconds = storedInterval == 0 ? 80 : storedInterval

        if let existing = defaults.string(forKey: Keys.clientID) {
            self.clientID = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Keys.clientID)
            self.clientID = generated
        }
    }
}
