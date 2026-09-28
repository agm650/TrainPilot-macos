import Foundation

public struct LocomotiveDraft: Equatable, Sendable {
    public var name: String
    public var dccAddress: Int
    public var addressKind: String
    public var speedSteps: Int
    public var manufacturer: String
    public var model: String

    public init(
        name: String = "",
        dccAddress: Int = 3,
        addressKind: String = "short",
        speedSteps: Int = 128,
        manufacturer: String = "",
        model: String = ""
    ) {
        self.name = name
        self.dccAddress = dccAddress
        self.addressKind = addressKind
        self.speedSteps = speedSteps
        self.manufacturer = manufacturer
        self.model = model
    }

    public var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Le nom est obligatoire."
        }
        if !(1...10_239).contains(dccAddress) {
            return "L’adresse DCC doit être comprise entre 1 et 10239."
        }
        if ![14, 28, 128].contains(speedSteps) {
            return "Le nombre de pas doit être 14, 28 ou 128."
        }
        return nil
    }

}
