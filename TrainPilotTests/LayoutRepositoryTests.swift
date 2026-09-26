import XCTest
@testable import TrainPilot

private enum LayoutDataSourceTestError: Error {
    case unavailable
}

private actor LayoutDataSourceSpy: LayoutDataSource {
    var topologyValue: TopologyDefinition
    var presentationValue: LayoutPresentationDefinition
    var topologyShouldFail = false
    var presentationShouldFail = false
    private(set) var topologyLoadCount = 0
    private(set) var presentationLoadCount = 0

    init(topologyRevision: String, presentationRevision: String) {
        topologyValue = Self.makeTopology(revision: topologyRevision)
        presentationValue = Self.makePresentation(revision: presentationRevision)
    }

    func topology() throws -> TopologyDefinition {
        topologyLoadCount += 1
        guard !topologyShouldFail else {
            throw LayoutDataSourceTestError.unavailable
        }
        return topologyValue
    }

    func layoutPresentation() throws -> LayoutPresentationDefinition {
        presentationLoadCount += 1
        guard !presentationShouldFail else {
            throw LayoutDataSourceTestError.unavailable
        }
        return presentationValue
    }

    func setTopologyRevision(_ revision: String) {
        topologyValue = Self.makeTopology(revision: revision)
    }

    func setPresentationRevision(_ revision: String) {
        presentationValue = Self.makePresentation(revision: revision)
    }

    func setTopologyShouldFail(_ shouldFail: Bool) {
        topologyShouldFail = shouldFail
    }

    func counts() -> (topology: Int, presentation: Int) {
        (topologyLoadCount, presentationLoadCount)
    }

    private static func makeTopology(revision: String) -> TopologyDefinition {
        TopologyDefinition(
            revision: revision,
            nodes: [],
            trackSections: [],
            turnoutTopologies: [],
            blocks: []
        )
    }

    private static func makePresentation(
        revision: String
    ) -> LayoutPresentationDefinition {
        LayoutPresentationDefinition(
            revision: revision,
            coordinateSystem: "layout-units",
            gridSpacing: 20,
            nodes: [],
            trackSections: [],
            turnouts: [],
            blocks: []
        )
    }
}

@MainActor
final class LayoutRepositoryTests: XCTestCase {
    func testUnchangedRevisionsDoNotReload() async throws {
        let (repository, source) = try await makeLoadedRepository()

        try await repository.refreshIfNeeded(
            topologyRevision: "topology-1",
            presentationRevision: "presentation-1"
        )

        let counts = await source.counts()
        XCTAssertEqual(counts.topology, 1)
        XCTAssertEqual(counts.presentation, 1)
    }

    func testOnlyTopologyRevisionReloadsTopology() async throws {
        let (repository, source) = try await makeLoadedRepository()
        await source.setTopologyRevision("topology-2")

        try await repository.refreshIfNeeded(
            topologyRevision: "topology-2",
            presentationRevision: "presentation-1"
        )

        let counts = await source.counts()
        XCTAssertEqual(counts.topology, 2)
        XCTAssertEqual(counts.presentation, 1)
        XCTAssertEqual(repository.topologyRevision, "topology-2")
    }

    func testOnlyPresentationRevisionReloadsPresentation() async throws {
        let (repository, source) = try await makeLoadedRepository()
        await source.setPresentationRevision("presentation-2")

        try await repository.refreshIfNeeded(
            topologyRevision: "topology-1",
            presentationRevision: "presentation-2"
        )

        let counts = await source.counts()
        XCTAssertEqual(counts.topology, 1)
        XCTAssertEqual(counts.presentation, 2)
        XCTAssertEqual(repository.presentationRevision, "presentation-2")
    }

    func testBothRevisionChangesReloadBothResources() async throws {
        let (repository, source) = try await makeLoadedRepository()
        await source.setTopologyRevision("topology-2")
        await source.setPresentationRevision("presentation-2")

        try await repository.refreshIfNeeded(
            topologyRevision: "topology-2",
            presentationRevision: "presentation-2"
        )

        let counts = await source.counts()
        XCTAssertEqual(counts.topology, 2)
        XCTAssertEqual(counts.presentation, 2)
    }

    func testReloadErrorKeepsPreviousSnapshot() async throws {
        let (repository, source) = try await makeLoadedRepository()
        let previousSnapshot = repository.snapshot
        await source.setTopologyRevision("topology-2")
        await source.setTopologyShouldFail(true)

        do {
            try await repository.refreshIfNeeded(
                topologyRevision: "topology-2",
                presentationRevision: "presentation-1"
            )
            XCTFail("The refresh should fail")
        } catch LayoutDataSourceTestError.unavailable {
            XCTAssertEqual(repository.snapshot, previousSnapshot)
            XCTAssertEqual(repository.availability, .stale)
        }
    }

    func testImportNotificationDoesNotMutateStateBeforeConfirmedRevisions() async throws {
        let (repository, source) = try await makeLoadedRepository()
        let previousSnapshot = repository.snapshot
        await source.setTopologyRevision("topology-2")
        await source.setPresentationRevision("presentation-2")

        XCTAssertEqual(repository.snapshot, previousSnapshot)
        let counts = await source.counts()
        XCTAssertEqual(counts.topology, 1)
        XCTAssertEqual(counts.presentation, 1)
    }

    private func makeLoadedRepository() async throws -> (
        LayoutRepository,
        LayoutDataSourceSpy
    ) {
        let source = LayoutDataSourceSpy(
            topologyRevision: "topology-1",
            presentationRevision: "presentation-1"
        )
        let repository = LayoutRepository(dataSource: source)
        try await repository.loadInitialState()
        return (repository, source)
    }
}
