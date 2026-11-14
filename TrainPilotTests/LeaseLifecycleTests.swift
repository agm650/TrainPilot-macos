import Combine
import Foundation
import Testing
@testable import TrainPilot

@MainActor
struct LeaseLifecycleTests {
    private func releasedEvent(_ lease: ControlLease) throws -> ServerEvent {
        var released = lease
        released.state = "released"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return ServerEvent(type: "locomotive.control.released", sequence: 1,
                           timestamp: nil, payload: try encoder.encode(released))
    }

    @Test func lateHeartbeatCannotReviveReleasedLease() async throws {
        let app = PreviewData.cab()
        let session = try #require(app.driving.activeSession)
        let response = session.lease
        app.markLeaseStopping(leaseID: response.id, locomotiveID: response.locomotiveId)
        #expect(app.leaseForLocomotive(response.locomotiveId)?.state == "stopping")
        app.applyLeaseRenewal(response, expectedSession: session)
        #expect(session.lease.state == "stopping")
        await app.handle(try releasedEvent(response))
        app.applyLeaseRenewal(response, expectedSession: session)
        #expect(app.driving.activeSession == nil)
        #expect(app.leaseForLocomotive(response.locomotiveId) == nil)
        app.driving.select(locomotiveID: response.locomotiveId)
        #expect(app.driving.activeSession == nil)
    }

    @Test func oldReleaseAndHeartbeatCannotRemoveNewLease() async throws {
        let app = PreviewData.cab()
        let oldSession = try #require(app.driving.activeSession)
        let oldLease = oldSession.lease
        await app.handle(try releasedEvent(oldLease))
        let newLease = ControlLease(
            id: "new-lease", locomotiveId: oldLease.locomotiveId, userId: oldLease.userId,
            sessionId: oldLease.sessionId, state: "active", acquiredAt: Date(), renewedAt: Date(),
            expiresAt: Date().addingTimeInterval(60), heartbeatMillis: 5000
        )
        app.knownLeases.append(newLease)
        let newSession = app.driving.add(locomotive: oldSession.locomotive, lease: newLease)
        await app.handle(try releasedEvent(oldLease))
        app.applyLeaseRenewal(oldLease, expectedSession: oldSession)
        #expect(app.driving.activeSession === newSession)
        #expect(app.leaseForLocomotive(newLease.locomotiveId)?.id == newLease.id)
    }

    @Test func stoppingSessionCannotBeSelectedOrAccelerated() async throws {
        let app = PreviewData.cab(selector: .forward)
        let session = try #require(app.driving.activeSession)
        app.markLeaseStopping(leaseID: session.lease.id, locomotiveID: session.id)
        app.driving.activeLocomotiveID = nil
        app.driving.select(locomotiveID: session.id)
        #expect(app.driving.activeSession == nil)
        await app.selectDirection(locomotiveID: session.id, position: .forward)
        app.setRequestedSpeed(locomotiveID: session.id, speed: 50)
        #expect(session.selectorPosition == .neutral)
        #expect(session.requestedSpeed == 0)
    }

    @Test func sessionChangesNotifyLibraryAndCab() throws {
        let app = PreviewData.cab()
        let session = try #require(app.driving.activeSession)
        var changes = 0
        let observation = app.objectWillChange.sink { changes += 1 }
        session.lease.state = "stopping"
        #expect(changes > 0)
        changes = 0
        app.driving.remove(locomotiveID: session.id)
        #expect(changes > 0)
        changes = 0
        session.lease.state = "released"
        #expect(changes == 0)
        _ = app.driving.add(locomotive: session.locomotive, lease: session.lease)
        #expect(changes > 0)
        changes = 0
        app.driving.activeLocomotiveID = nil
        #expect(changes > 0)
        withExtendedLifetime(observation) {}
    }

    @Test func currentHeartbeatStillUpdatesActiveLease() throws {
        let app = PreviewData.cab()
        let session = try #require(app.driving.activeSession)
        var response = session.lease
        response.expiresAt = Date().addingTimeInterval(1200)
        app.applyLeaseRenewal(response, expectedSession: session)
        #expect(session.lease.expiresAt == response.expiresAt)
        #expect(app.leaseForLocomotive(session.id)?.expiresAt == response.expiresAt)
    }
}
