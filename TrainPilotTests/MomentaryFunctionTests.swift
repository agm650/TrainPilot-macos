import Foundation
import Testing
@testable import TrainPilot

@MainActor
private final class FunctionTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
struct MomentaryFunctionTests {
    private let key = MomentaryFunctionController.Key(
        locomotiveID: "loco", leaseID: "lease", function: 2
    )

    private func controller() -> MomentaryFunctionController {
        let result = MomentaryFunctionController()
        result.canSend = { _, _ in true }
        return result
    }

    @Test func quickReleaseWaitsForInFlightON() async throws {
        let controller = controller()
        let started = FunctionTestGate()
        let finish = FunctionTestGate()
        var commands: [Bool] = []
        controller.send = { _, enabled in
            commands.append(enabled)
            if enabled {
                started.open()
                await finish.wait()
            }
        }
        let token = try #require(controller.press(key))
        await started.wait()
        controller.release(token)
        #expect(commands == [true])
        finish.open()
        await controller.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func cancelledBeforeDispatchDoesNotSendON() async throws {
        let controller = controller()
        var commands: [Bool] = []
        controller.send = { _, enabled in commands.append(enabled) }
        let token = try #require(controller.press(key))
        controller.release(token)
        await controller.waitForPendingCommands()
        #expect(commands.isEmpty)
    }

    @Test func mouseAndKeyboardShareOneHold() async throws {
        let controller = controller()
        var commands: [Bool] = []
        controller.send = { _, enabled in commands.append(enabled) }
        let mouse = try #require(controller.press(key))
        let keyboard = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        controller.release(mouse)
        await controller.waitForPendingCommands()
        #expect(commands == [true])
        controller.release(keyboard)
        controller.release(keyboard)
        await controller.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func newPressCannotOvertakePreviousOFF() async throws {
        let controller = controller()
        var commands: [Bool] = []
        controller.send = { _, enabled in commands.append(enabled) }
        let first = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        controller.release(first)
        let second = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        controller.release(second)
        await controller.waitForPendingCommands()
        #expect(commands == [true, false, true, false])
    }

    @Test func failedONStillSendsOFF() async throws {
        let controller = controller()
        var commands: [Bool] = []
        var failures = 0
        controller.send = { _, enabled in
            commands.append(enabled)
            if enabled { throw URLError(.timedOut) }
        }
        controller.onFailure = { _ in failures += 1 }
        _ = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        #expect(commands == [true, false])
        #expect(failures == 1)
    }

    @Test func failedOFFInvokesRecovery() async throws {
        let controller = controller()
        var failures = 0
        controller.send = { _, enabled in
            if !enabled { throw URLError(.networkConnectionLost) }
        }
        controller.onFailure = { _ in failures += 1 }
        let token = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        controller.release(token)
        await controller.waitForPendingCommands()
        #expect(failures == 1)
    }

    @Test func disconnectCancelsQueuedPressAcrossReconnect() async throws {
        let controller = controller()
        var commands: [Bool] = []
        controller.send = { _, enabled in commands.append(enabled) }
        _ = try #require(controller.press(key))
        controller.releaseAll()
        await controller.waitForPendingCommands()
        #expect(commands.isEmpty)
        let fresh = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        controller.release(fresh)
        await controller.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func ownershipIsRecheckedBeforeDispatch() async throws {
        let controller = controller()
        var ownsLease = true
        var commands: [Bool] = []
        controller.canSend = { _, _ in ownsLease }
        controller.send = { _, enabled in commands.append(enabled) }
        _ = try #require(controller.press(key))
        ownsLease = false
        await controller.waitForPendingCommands()
        controller.releaseAll()
        await controller.waitForPendingCommands()
        #expect(commands.isEmpty)
        #expect(controller.press(key) == nil)
    }

    @Test func OFFRemainsPossibleWhenTractionIsDisabled() async throws {
        let controller = controller()
        var tractionEnabled = true
        var commands: [Bool] = []
        controller.canSend = { _, enabled in !enabled || tractionEnabled }
        controller.send = { _, enabled in commands.append(enabled) }
        let token = try #require(controller.press(key))
        await controller.waitForPendingCommands()
        tractionEnabled = false
        #expect(controller.press(key) == nil)
        controller.release(token)
        await controller.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func appDisconnectReleasesHeldFunctions() async throws {
        let app = AppModel()
        var commands: [Bool] = []
        app.momentaryFunctions.canSend = { _, _ in true }
        app.momentaryFunctions.send = { _, enabled in commands.append(enabled) }
        app.connectionState = .ready
        _ = try #require(app.momentaryFunctions.press(key))
        await app.momentaryFunctions.waitForPendingCommands()
        app.connectionState = .reconnecting
        await app.momentaryFunctions.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func selectionChangeReleasesHeldFunctions() async throws {
        let app = PreviewData.cab()
        var commands: [Bool] = []
        app.momentaryFunctions.canSend = { _, _ in true }
        app.momentaryFunctions.send = { _, enabled in commands.append(enabled) }
        _ = try #require(app.momentaryFunctions.press(key))
        await app.momentaryFunctions.waitForPendingCommands()
        app.driving.activeLocomotiveID = nil
        await app.momentaryFunctions.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func emergencyStopReleasesHeldFunctions() async throws {
        let app = PreviewData.cab()
        var commands: [Bool] = []
        app.momentaryFunctions.canSend = { _, _ in true }
        app.momentaryFunctions.send = { _, enabled in commands.append(enabled) }
        _ = try #require(app.momentaryFunctions.press(key))
        await app.momentaryFunctions.waitForPendingCommands()
        app.stationStatus.emergencyStop = true
        await app.momentaryFunctions.waitForPendingCommands()
        #expect(commands == [true, false])
    }

    @Test func keyboardUninstallReleasesMouseAndKeyboardHolds() async throws {
        let app = AppModel()
        var commands: [Bool] = []
        app.momentaryFunctions.canSend = { _, _ in true }
        app.momentaryFunctions.send = { _, enabled in commands.append(enabled) }
        _ = try #require(app.momentaryFunctions.press(key))
        await app.momentaryFunctions.waitForPendingCommands()
        KeyboardController(appModel: app).uninstall()
        await app.momentaryFunctions.waitForPendingCommands()
        #expect(commands == [true, false])
    }
}

@MainActor
struct FunctionDefinitionTests {
    private let legacyJSON = """
    {"id":"loco","name":"Test","dccAddress":3,"addressKind":"short","speedSteps":128}
    """

    @Test func missingDefinitionsAndMissingFlagDefaultToToggle() throws {
        let locomotive = try JSONDecoder().decode(Locomotive.self, from: Data(legacyJSON.utf8))
        #expect(!locomotive.isMomentary(2))
        let definition = try JSONDecoder().decode(
            LocomotiveFunction.self, from: Data(#"{"number":2}"#.utf8)
        )
        #expect(!definition.momentary)
    }

    @Test func definitionsRoundTripAndPreserveExplicitClear() throws {
        var locomotive = try JSONDecoder().decode(Locomotive.self, from: Data(legacyJSON.utf8))
        locomotive.functions = [.init(number: 2, momentary: true), .init(number: 68)]
        let data = try JSONEncoder().encode(locomotive)
        let decoded = try JSONDecoder().decode(Locomotive.self, from: data)
        #expect(decoded.isMomentary(2))
        #expect(!decoded.isMomentary(68))
        #expect(LocomotiveInput(locomotive: decoded).functions == locomotive.functions)
        locomotive.functions = []
        let cleared = try JSONEncoder().encode(LocomotiveInput(locomotive: locomotive))
        let object = try #require(JSONSerialization.jsonObject(with: cleared) as? [String: Any])
        #expect((object["functions"] as? [Any])?.isEmpty == true)
        locomotive.functions = nil
        let omitted = try JSONEncoder().encode(LocomotiveInput(locomotive: locomotive))
        let old = try #require(JSONSerialization.jsonObject(with: omitted) as? [String: Any])
        #expect(old["functions"] == nil)
    }

    @Test func snapshotIncludesDefinitions() throws {
        let data = Data("""
        {"type":"system.snapshot","sequence":1,"payload":{"locomotives":[
        {"id":"loco","name":"Test","dccAddress":3,"addressKind":"short","speedSteps":128,
         "functions":[{"number":2,"momentary":true}]}]}}
        """.utf8)
        let snapshot = try JSONDecoder.trainPilot.decode(SystemSnapshot.self, from: data)
        #expect(snapshot.payload.locomotives?.first?.isMomentary(2) == true)
    }

    @Test func updatesReachExistingDrivingSession() async throws {
        let app = PreviewData.cab()
        let session = try #require(app.driving.activeSession)
        var locomotive = session.locomotive
        locomotive.functions = [.init(number: 2, momentary: true)]
        let event = ServerEvent(
            type: "locomotive.updated", sequence: 1, timestamp: nil,
            payload: try JSONEncoder().encode(locomotive)
        )
        await app.handle(event)
        #expect(session.locomotive.isMomentary(2))
        #expect(app.locomotives.first?.isMomentary(2) == true)
    }

    @Test func configurationRequiresNewContractAndHonorsStationLimit() throws {
        let app = PreviewData.cab()
        #expect(!app.supportsMomentaryFunctions)
        let old = try #require(app.systemInfo)
        app.systemInfo = SystemInfo(
            serverVersion: "test", apiVersion: "1.14.0", minimumClientApiVersion: "1.4.0",
            eventApiVersion: "1.13.0", minimumClientEventApiVersion: "1.0.0", station: old.station
        )
        #expect(app.supportsMomentaryFunctions)
        #expect(app.availableFunctionCount == 13)
    }

    @Test func serverOFFUpdatesIndicator() async throws {
        let app = PreviewData.cab()
        let session = try #require(app.driving.activeSession)
        let data = try JSONSerialization.data(withJSONObject: [
            "locomotiveId": session.id, "function": 2, "enabled": false
        ])
        await app.handle(ServerEvent(
            type: "locomotive.function.changed", sequence: 1, timestamp: nil, payload: data
        ))
        #expect(session.functionStates[2] == false)
    }
}
