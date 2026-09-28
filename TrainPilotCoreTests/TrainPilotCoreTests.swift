import Foundation
import Testing
@testable import TrainPilotCore

struct ServerConfigurationTests {
    @Test func addsDefaultHTTPscheme() throws {
        let configuration = try #require(ServerConfiguration(serverAddress: "192.168.1.10:8080"))

        #expect(configuration.baseURL.absoluteString == "http://192.168.1.10:8080")
        #expect(configuration.webSocketURL?.absoluteString == "ws://192.168.1.10:8080/api/v1/events")
    }

    @Test func mapsHTTPSWebSocketAndDropsQuery() throws {
        let configuration = try #require(
            ServerConfiguration(serverAddress: "https://rail.example:8443/base?token=ignored")
        )

        #expect(configuration.webSocketURL?.absoluteString == "wss://rail.example:8443/api/v1/events")
    }

    @Test(
        "Rejects unsupported or incomplete server addresses",
        arguments: ["", "ftp://rail.example", "http:///missing-host"]
    )
    func rejectsInvalidAddress(_ address: String) {
        #expect(ServerConfiguration(serverAddress: address) == nil)
    }
}

struct LocomotiveDraftTests {
    @Test func acceptsSupportedFields() {
        let draft = LocomotiveDraft(
            name: "BB 26000",
            dccAddress: 260,
            addressKind: "long",
            speedSteps: 128,
            manufacturer: "Jouef",
            model: "Sybic"
        )

        #expect(draft.validationMessage == nil)
    }

    @Test(
        "Validates required name, DCC range, and speed steps",
        arguments: [
            LocomotiveDraft(name: " ", dccAddress: 3, speedSteps: 128),
            LocomotiveDraft(name: "BB", dccAddress: 0, speedSteps: 128),
            LocomotiveDraft(name: "BB", dccAddress: 3, speedSteps: 27)
        ]
    )
    func rejectsInvalidDraft(_ draft: LocomotiveDraft) {
        #expect(draft.validationMessage != nil)
    }
}

struct OperationalStatusTests {
    @Test func distinguishesAdministratorFromDriver() {
        #expect(SessionIdentity(username: "admin", role: "administrator").isAdministrator)
        #expect(!SessionIdentity(username: "driver", role: "driver").isAdministrator)
    }

    @Test func preservesStableRawValues() {
        #expect(ClientConnectionState.reconnecting.rawValue == "reconnecting")
        #expect(CommandStationConnectivity.degraded.rawValue == "degraded")
        #expect(TrackPowerStatus.unknown.rawValue == "unknown")
    }
}

struct TransferArchiveTests {
    @Test func preservesOpaqueZipPayload() {
        let payload = Data([0x50, 0x4b, 0x03, 0x04])
        let archive = TransferArchive(
            data: payload,
            suggestedFilename: "TrainPilot-rolling-stock.zip"
        )

        #expect(archive.data == payload)
        #expect(archive.suggestedFilename.hasSuffix(".zip"))
    }
}
