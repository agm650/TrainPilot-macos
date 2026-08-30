import Foundation
import Combine

@MainActor
final class DrivingSessionManager: ObservableObject {
    @Published private(set) var sessions: [String: DrivingSession] = [:]
    @Published var activeLocomotiveID: String?

    var activeSession: DrivingSession? {
        guard let activeLocomotiveID else { return nil }
        return sessions[activeLocomotiveID]
    }

    var sortedSessions: [DrivingSession] {
        sessions.values.sorted {
            $0.locomotive.name.localizedCaseInsensitiveCompare($1.locomotive.name) == .orderedAscending
        }
    }

    func add(locomotive: Locomotive, lease: ControlLease, makeActive: Bool = true) -> DrivingSession {
        if let existing = sessions[locomotive.id] {
            existing.lease = lease
            if makeActive { activeLocomotiveID = locomotive.id }
            return existing
        }

        let session = DrivingSession(locomotive: locomotive, lease: lease)
        sessions[locomotive.id] = session

        if makeActive || activeLocomotiveID == nil {
            activeLocomotiveID = locomotive.id
        }
        return session
    }

    func remove(locomotiveID: String) {
        sessions.removeValue(forKey: locomotiveID)
        if activeLocomotiveID == locomotiveID {
            activeLocomotiveID = sortedSessions.first?.locomotive.id
        }
    }

    func removeAll() {
        sessions.removeAll()
        activeLocomotiveID = nil
    }

    func select(locomotiveID: String) {
        guard sessions[locomotiveID] != nil else { return }
        activeLocomotiveID = locomotiveID
    }
}
