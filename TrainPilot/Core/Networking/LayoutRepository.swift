import Combine
import Foundation

protocol LayoutDataSource: Sendable {
    func topology() async throws -> TopologyDefinition
    func layoutPresentation() async throws -> LayoutPresentationDefinition
}

enum LayoutAvailability: Equatable {
    case loading
    case ready
    case unavailable
    case stale
}

struct LayoutSnapshot: Equatable, Sendable {
    let topology: TopologyDefinition
    let presentation: LayoutPresentationDefinition
}

enum LayoutRepositoryError: Error, Equatable {
    case revisionMismatch(resource: String, expected: String, received: String)
}

@MainActor
final class LayoutRepository: ObservableObject {
    @Published private(set) var snapshot: LayoutSnapshot?
    @Published private(set) var availability: LayoutAvailability = .unavailable

    private let dataSource: any LayoutDataSource

    init(dataSource: any LayoutDataSource) {
        self.dataSource = dataSource
    }

    var topology: TopologyDefinition? {
        snapshot?.topology
    }

    var presentation: LayoutPresentationDefinition? {
        snapshot?.presentation
    }

    var topologyRevision: String? {
        topology?.revision
    }

    var presentationRevision: String? {
        presentation?.revision
    }

    func loadInitialState() async throws {
        availability = .loading

        do {
            async let topology = dataSource.topology()
            async let presentation = dataSource.layoutPresentation()
            snapshot = try await LayoutSnapshot(
                topology: topology,
                presentation: presentation
            )
            availability = .ready
        } catch {
            availability = snapshot == nil ? .unavailable : .stale
            throw error
        }
    }

    func refreshIfNeeded(
        topologyRevision: String,
        presentationRevision: String
    ) async throws {
        guard let current = snapshot else {
            try await loadExpectedState(
                topologyRevision: topologyRevision,
                presentationRevision: presentationRevision
            )
            return
        }

        let reloadTopology = current.topology.revision != topologyRevision
        let reloadPresentation = current.presentation.revision != presentationRevision

        guard reloadTopology || reloadPresentation else {
            return
        }

        availability = .loading

        do {
            var nextTopology = current.topology
            var nextPresentation = current.presentation

            if reloadTopology && reloadPresentation {
                async let topology = dataSource.topology()
                async let presentation = dataSource.layoutPresentation()
                (nextTopology, nextPresentation) = try await (topology, presentation)
            } else if reloadTopology {
                nextTopology = try await dataSource.topology()
            } else {
                nextPresentation = try await dataSource.layoutPresentation()
            }

            try validateRevision(
                nextTopology.revision,
                expected: topologyRevision,
                resource: "topology"
            )
            try validateRevision(
                nextPresentation.revision,
                expected: presentationRevision,
                resource: "layout presentation"
            )

            snapshot = LayoutSnapshot(
                topology: nextTopology,
                presentation: nextPresentation
            )
            availability = .ready
        } catch {
            availability = .stale
            throw error
        }
    }

    private func loadExpectedState(
        topologyRevision: String,
        presentationRevision: String
    ) async throws {
        availability = .loading

        do {
            async let topology = dataSource.topology()
            async let presentation = dataSource.layoutPresentation()
            let (loadedTopology, loadedPresentation) = try await (
                topology,
                presentation
            )

            try validateRevision(
                loadedTopology.revision,
                expected: topologyRevision,
                resource: "topology"
            )
            try validateRevision(
                loadedPresentation.revision,
                expected: presentationRevision,
                resource: "layout presentation"
            )

            snapshot = LayoutSnapshot(
                topology: loadedTopology,
                presentation: loadedPresentation
            )
            availability = .ready
        } catch {
            availability = .unavailable
            throw error
        }
    }

    private func validateRevision(
        _ received: String,
        expected: String,
        resource: String
    ) throws {
        guard received == expected else {
            throw LayoutRepositoryError.revisionMismatch(
                resource: resource,
                expected: expected,
                received: received
            )
        }
    }
}
