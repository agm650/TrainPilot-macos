import Foundation
import Combine

@MainActor
final class DrivingSessionManager: ObservableObject {
    @Published private(set) var sessions: [String: DrivingSession] = [:]
    @Published var activeLocomotiveID: String? {
        didSet {
            if oldValue != activeLocomotiveID { onSelectionChange?() }
        }
    }
    var onSelectionChange: (() -> Void)?
    private var leaseObservations: [String: AnyCancellable] = [:]

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
            existing.locomotive = locomotive
            existing.lease = lease
            if makeActive { activeLocomotiveID = locomotive.id }
            return existing
        }

        let session = DrivingSession(locomotive: locomotive, lease: lease)
        leaseObservations[locomotive.id] = session.$lease.dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        sessions[locomotive.id] = session

        if makeActive || activeLocomotiveID == nil {
            activeLocomotiveID = locomotive.id
        }
        return session
    }

    func remove(locomotiveID: String) {
        leaseObservations.removeValue(forKey: locomotiveID)
        sessions.removeValue(forKey: locomotiveID)
        if activeLocomotiveID == locomotiveID {
            activeLocomotiveID = sortedSessions.first?.locomotive.id
        }
    }

    func removeAll() {
        leaseObservations.removeAll()
        sessions.removeAll()
        activeLocomotiveID = nil
    }

    func select(locomotiveID: String) {
        guard sessions[locomotiveID]?.lease.state == "active" else { return }
        activeLocomotiveID = locomotiveID
    }
}
