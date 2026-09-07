// #if DEBUG
import Foundation

@MainActor
enum PreviewData {
    static func cab(
        connectivity: StationConnectivity = .online,
        trackPower: TrackPowerState = .on,
        emergencyStop: Bool = false,
        selector: DirectionSelectorPosition = .neutral,
        requestedSpeed: Int = 0,
        confirmedSpeed: Int? = 0,
        direction: DCCDirection = .forward
    ) -> AppModel {
        let appModel = AppModel()

        appModel.connectionState = .ready

        appModel.systemInfo = SystemInfo(
            serverVersion: "preview",
            apiVersion: "1.0.0",
            minimumClientApiVersion: "1.0.0",
            eventApiVersion: "1.0.0",
            minimumClientEventApiVersion: "1.0.0",
            station: Capabilities(
                driver: "preview",
                trackPower: true,
                locomotiveControl: true,
                functions: 13,
                maxFunctionNumber: 12,
                accessoryControl: true,
                feedback: true
            )
        )

        appModel.stationStatus = StationStatus(
            connectivity: connectivity,
            lastSeen: Date(),
            trackPower: trackPower,
            emergencyStop: emergencyStop,
            shortCircuit: false,
            programmingMode: false,
            mainCurrentMilliAmps: 350,
            programmingCurrentMilliAmps: 0,
            filteredMainCurrentMilliAmps: 340,
            temperatureCelsius: 32,
            supplyVoltageMilliVolts: 18_000,
            trackVoltageMilliVolts: 16_000,
            highTemperature: false,
            powerLost: false,
            externalShortCircuit: false,
            internalShortCircuit: false
        )

        let now = Date()

        appModel.currentUser = User(
            id: "preview-user",
            username: "preview",
            displayName: "Preview Driver",
            role: "administrator",
            enabled: true,
            mustChangePassword: false,
            createdAt: now,
            updatedAt: now,
            lastLoginAt: now
        )

        let locomotive = Locomotive(
            id: "preview-locomotive",
            name: "BB 407233",
            dccAddress: 29,
            addressKind: "short",
            speedSteps: 128,
            manufacturer: "Alstom",
            model: "BB 36000"
        )

        let lease = ControlLease(
            id: "preview-lease",
            locomotiveId: locomotive.id,
            userId: "preview-user",
            sessionId: "preview-session",
            state: "active",
            acquiredAt: now,
            renewedAt: now,
            expiresAt: now.addingTimeInterval(600),
            releaseAfter: nil,
            releaseReason: nil,
            heartbeatMillis: 5_000
        )

        appModel.locomotives = [locomotive]
        appModel.knownLeases = [lease]

        let session = appModel.driving.add(
            locomotive: locomotive,
            lease: lease
        )

        session.selectorPosition = selector
        session.requestedSpeed = requestedSpeed
        session.confirmedSpeed = confirmedSpeed
        session.direction = direction

        session.setFunction(0, enabled: true)
        session.setFunction(2, enabled: true)
        session.setFunction(5, enabled: true)

        return appModel
    }

    static func emptyCab(
        connectivity: StationConnectivity = .online
    ) -> AppModel {
        let appModel = AppModel()

        appModel.connectionState = .ready
        appModel.stationStatus = StationStatus(
            connectivity: connectivity,
            lastSeen: Date(),
            trackPower: connectivity == .online ? .on : .unknown,
            emergencyStop: false,
            shortCircuit: false,
            programmingMode: false,
            mainCurrentMilliAmps: 0,
            programmingCurrentMilliAmps: 0,
            filteredMainCurrentMilliAmps: 0,
            temperatureCelsius: 0,
            supplyVoltageMilliVolts: 0,
            trackVoltageMilliVolts: 0,
            highTemperature: false,
            powerLost: false,
            externalShortCircuit: false,
            internalShortCircuit: false
        )

        return appModel
    }
}
// #endif
