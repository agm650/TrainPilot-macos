import Foundation
import Combine

@MainActor
final class DrivingSession: ObservableObject, Identifiable {
    nonisolated let id: String

    let locomotive: Locomotive

    @Published var lease: ControlLease
    @Published var requestedSpeed: Int = 0
    @Published var confirmedSpeed: Int?
    @Published var direction: DCCDirection = .forward
    @Published var selectorPosition: DirectionSelectorPosition = .neutral
    @Published var functionStates: [Int: Bool] = [:]
    @Published var commandInFlight = false

    init(locomotive: Locomotive, lease: ControlLease) {
        self.id = locomotive.id
        self.locomotive = locomotive
        self.lease = lease
    }

    var isNeutral: Bool {
        selectorPosition == .neutral
    }

    func setFunction(_ number: Int, enabled: Bool) {
        var updated = functionStates
        updated[number] = enabled
        functionStates = updated
    }
}
