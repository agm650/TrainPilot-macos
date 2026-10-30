import Testing
@testable import TrainPilot

struct RBusContactAddressTests {
    @Test(arguments: [1, 8, 9, 17, 80, 81, 160])
    func roundTripPreservesExistingContacts(_ address: Int) throws {
        let contact = try #require(RBusContactAddress(globalAddress: address))
        #expect(try contact.globalAddress() == address)
        #expect((1...8).contains(contact.input))
    }

    @Test func detectorAndInputAreConvertedToServerAddress() throws {
        #expect(try RBusContactAddress(detector: 3, input: 5).globalAddress() == 21)
        #expect(RBusContactAddress(globalAddress: 17) == RBusContactAddress(detector: 3, input: 1))
    }

    @Test func invalidValuesAreRejected() {
        for contact in [
            RBusContactAddress(detector: 0, input: 1),
            RBusContactAddress(detector: -1, input: 1),
            RBusContactAddress(detector: 1, input: 0),
            RBusContactAddress(detector: 1, input: 9),
            RBusContactAddress(detector: Int.max, input: 8)
        ] {
            #expect(throws: TurnoutConfigurationError.self) { try contact.globalAddress() }
        }
        #expect(RBusContactAddress(globalAddress: 0) == nil)
    }
}
