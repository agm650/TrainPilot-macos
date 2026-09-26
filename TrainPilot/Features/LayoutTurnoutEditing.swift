import Foundation

struct TurnoutPaletteItem: Equatable, Identifiable {
    let kind: TurnoutKind
    let title: String
    let portCount: Int
    let isEditable: Bool

    var id: TurnoutKind { kind }

    static let all: [TurnoutPaletteItem] = [
        TurnoutPaletteItem(kind: .simple, title: "Simple", portCount: 3, isEditable: true),
        TurnoutPaletteItem(kind: .threeWay, title: "Triple", portCount: 4, isEditable: true),
        TurnoutPaletteItem(kind: .doubleSlip, title: "TJD", portCount: 4, isEditable: true),
        TurnoutPaletteItem(kind: .singleSlip, title: "TJS", portCount: 4, isEditable: true),
        TurnoutPaletteItem(kind: .custom, title: "Personnalisé", portCount: 0, isEditable: false)
    ]
}

enum TurnoutValidationIssue: Equatable {
    case missingEndpoint(String)
    case invalidAddress(turnoutID: String, address: Int)
    case duplicateAddress(Int)
    case duplicateEndpointID(turnoutID: String, endpointID: String)
    case incompletePosition(turnoutID: String, positionID: String)
    case missingTopology(String)
    case missingPresentation(String)
}

struct TurnoutValidator {
    func validate(
        definitions: [TurnoutDefinition],
        topology: TopologyDefinition,
        presentation: LayoutPresentationDefinition
    ) -> [TurnoutValidationIssue] {
        var issues: [TurnoutValidationIssue] = []
        var addresses: [Int: Int] = [:]

        for definition in definitions {
            if definition.endpoints.isEmpty {
                issues.append(.missingEndpoint(definition.id))
            }
            let grouped = Dictionary(grouping: definition.endpoints, by: \.id)
            for (endpointID, values) in grouped where values.count > 1 {
                issues.append(
                    .duplicateEndpointID(
                        turnoutID: definition.id,
                        endpointID: endpointID
                    )
                )
            }
            for endpoint in definition.endpoints {
                if !(1...2040).contains(endpoint.linearAddress) {
                    issues.append(
                        .invalidAddress(
                            turnoutID: definition.id,
                            address: endpoint.linearAddress
                        )
                    )
                }
                addresses[endpoint.linearAddress, default: 0] += 1
            }
            let endpointIDs = Set(definition.endpoints.map(\.id))
            for position in definition.positions
            where Set(position.endpoints.keys) != endpointIDs {
                issues.append(
                    .incompletePosition(
                        turnoutID: definition.id,
                        positionID: position.id
                    )
                )
            }
            if !topology.turnoutTopologies.contains(where: {
                $0.turnoutId == definition.id
            }) {
                issues.append(.missingTopology(definition.id))
            }
            if !presentation.turnouts.contains(where: {
                $0.turnoutId == definition.id
            }) {
                issues.append(.missingPresentation(definition.id))
            }
        }
        for (address, count) in addresses where count > 1 {
            issues.append(.duplicateAddress(address))
        }
        return issues
    }
}

extension LayoutEditorController {
    @discardableResult
    func addTurnout(
        id: String = UUID().uuidString,
        name: String = "Nouvel aiguillage",
        kind: TurnoutKind,
        position: LayoutPoint,
        firstAddress: Int,
        transform: LayoutViewportTransform,
        snapEnabled: Bool,
        optionKeyPressed: Bool
    ) throws -> String {
        guard kind != .custom else {
            throw LayoutEditError.missingResource("custom turnout template")
        }
        let center = transform.snapped(
            position,
            gridSpacing: document.presentation.gridSpacing,
            enabled: snapEnabled && !optionKeyPressed
        )
        let template = TurnoutTemplate(kind: kind, firstAddress: firstAddress)
        let ports = template.portOffsets.enumerated().map { index, offset in
            TurnoutPort(id: template.portIDs[index], nodeId: "\(id)-node-\(index)")
        }
        let nodes = ports.enumerated().map { index, port in
            TopologyNode(id: port.nodeId, name: nil, kind: .joint)
        }
        let positions = ports.enumerated().map { index, port in
            LayoutNodePosition(
                nodeId: port.nodeId,
                x: center.x + template.portOffsets[index].x,
                y: center.y + template.portOffsets[index].y
            )
        }
        let topology = document.topology.replacing(
            nodes: document.topology.nodes + nodes,
            turnoutTopologies: document.topology.turnoutTopologies + [
                TurnoutTopology(
                    turnoutId: id,
                    ports: ports,
                    positions: template.topologyPositions
                )
            ]
        )
        let presentation = document.presentation.replacing(
            nodes: document.presentation.nodes + positions,
            turnouts: document.presentation.turnouts + [
                LayoutTurnoutPresentation(
                    turnoutId: id,
                    x: center.x,
                    y: center.y,
                    rotationDegrees: 0,
                    mirrored: false
                )
            ]
        )
        let definition = TurnoutDefinition(
            id: id,
            name: name,
            kind: kind,
            endpoints: template.endpoints,
            positions: template.logicalPositions
        )

        performMutation {
            document.replaceEditingState(
                snapshot: LayoutSnapshot(
                    topology: topology,
                    presentation: presentation
                ),
                turnoutDefinitions: document.turnoutDefinitions + [definition]
            )
        }
        select(.turnout(id))
        return id
    }

    func transformTurnout(
        id: String,
        rotationDegrees: Double? = nil,
        mirrored: Bool? = nil
    ) throws {
        guard document.presentation.turnouts.contains(where: {
            $0.turnoutId == id
        }) else {
            throw LayoutEditError.missingResource(id)
        }
        let turnouts = document.presentation.turnouts.map { turnout in
            guard turnout.turnoutId == id else { return turnout }
            return LayoutTurnoutPresentation(
                turnoutId: id,
                x: turnout.x,
                y: turnout.y,
                rotationDegrees: rotationDegrees ?? turnout.rotationDegrees,
                mirrored: mirrored ?? turnout.mirrored
            )
        }
        performMutation {
            document.replacePresentation(document.presentation.replacing(turnouts: turnouts))
        }
    }

    func updateTurnoutEndpoint(
        turnoutID: String,
        endpointID: String,
        linearAddress: Int,
        inverted: Bool
    ) throws {
        guard let definitionIndex = document.turnoutDefinitions.firstIndex(where: {
            $0.id == turnoutID
        }) else {
            throw LayoutEditError.missingResource(turnoutID)
        }
        var definitions = document.turnoutDefinitions
        let definition = definitions[definitionIndex]
        guard definition.endpoints.contains(where: { $0.id == endpointID }) else {
            throw LayoutEditError.missingResource(endpointID)
        }
        let endpoints = definition.endpoints.map { endpoint in
            endpoint.id == endpointID
                ? AccessoryEndpoint(
                    id: endpointID,
                    linearAddress: linearAddress,
                    inverted: inverted
                )
                : endpoint
        }
        definitions[definitionIndex] = TurnoutDefinition(
            id: definition.id,
            name: definition.name,
            kind: definition.kind,
            endpoints: endpoints,
            positions: definition.positions
        )
        performMutation {
            document.replaceTurnoutDefinitions(definitions)
        }
    }
}

private struct TurnoutTemplate {
    let kind: TurnoutKind
    let endpoints: [AccessoryEndpoint]
    let portIDs: [String]
    let portOffsets: [LayoutPoint]
    let logicalPositions: [TurnoutPositionDefinition]
    let topologyPositions: [TurnoutTopologyPosition]

    init(kind: TurnoutKind, firstAddress: Int) {
        self.kind = kind
        switch kind {
        case .simple:
            endpoints = [AccessoryEndpoint(id: "main", linearAddress: firstAddress, inverted: false)]
            portIDs = ["stem", "straight", "diverging"]
            portOffsets = [
                LayoutPoint(x: -20, y: 0),
                LayoutPoint(x: 20, y: 0),
                LayoutPoint(x: 20, y: 20)
            ]
            logicalPositions = [
                TurnoutPositionDefinition(
                    id: "straight", label: "Droit", endpoints: ["main": .position1]
                ),
                TurnoutPositionDefinition(
                    id: "diverging", label: "Dévié", endpoints: ["main": .position2]
                )
            ]
            topologyPositions = [
                TurnoutTopologyPosition(
                    positionId: "straight",
                    connections: [PortConnection(portAId: "stem", portBId: "straight")]
                ),
                TurnoutTopologyPosition(
                    positionId: "diverging",
                    connections: [PortConnection(portAId: "stem", portBId: "diverging")]
                )
            ]

        case .threeWay:
            endpoints = [
                AccessoryEndpoint(id: "a", linearAddress: firstAddress, inverted: false),
                AccessoryEndpoint(id: "b", linearAddress: firstAddress + 1, inverted: false)
            ]
            portIDs = ["stem", "left", "straight", "right"]
            portOffsets = [
                LayoutPoint(x: -20, y: 0), LayoutPoint(x: 20, y: -20),
                LayoutPoint(x: 20, y: 0), LayoutPoint(x: 20, y: 20)
            ]
            logicalPositions = Self.positions(
                ids: ["left", "straight", "right"],
                vectors: [
                    ["a": .position2, "b": .position1],
                    ["a": .position1, "b": .position1],
                    ["a": .position1, "b": .position2]
                ]
            )
            topologyPositions = Self.connections(
                ids: ["left", "straight", "right"], stem: "stem"
            )

        case .doubleSlip, .singleSlip:
            endpoints = [
                AccessoryEndpoint(id: "a", linearAddress: firstAddress, inverted: false),
                AccessoryEndpoint(id: "b", linearAddress: firstAddress + 1, inverted: false)
            ]
            portIDs = ["northWest", "northEast", "southWest", "southEast"]
            portOffsets = [
                LayoutPoint(x: -20, y: -20), LayoutPoint(x: 20, y: -20),
                LayoutPoint(x: -20, y: 20), LayoutPoint(x: 20, y: 20)
            ]
            logicalPositions = Self.positions(
                ids: ["straight", "crossed"],
                vectors: [
                    ["a": .position1, "b": .position1],
                    ["a": .position2, "b": .position2]
                ]
            )
            topologyPositions = [
                TurnoutTopologyPosition(
                    positionId: "straight",
                    connections: [
                        PortConnection(portAId: "northWest", portBId: "southWest"),
                        PortConnection(portAId: "northEast", portBId: "southEast")
                    ]
                ),
                TurnoutTopologyPosition(
                    positionId: "crossed",
                    connections: [
                        PortConnection(portAId: "northWest", portBId: "southEast"),
                        PortConnection(portAId: "northEast", portBId: "southWest")
                    ]
                )
            ]

        case .custom:
            endpoints = []
            portIDs = []
            portOffsets = []
            logicalPositions = []
            topologyPositions = []
        }
    }

    private static func positions(
        ids: [String],
        vectors: [[String: AccessoryPosition]]
    ) -> [TurnoutPositionDefinition] {
        zip(ids, vectors).map {
            TurnoutPositionDefinition(id: $0.0, label: nil, endpoints: $0.1)
        }
    }

    private static func connections(
        ids: [String],
        stem: String
    ) -> [TurnoutTopologyPosition] {
        ids.map {
            TurnoutTopologyPosition(
                positionId: $0,
                connections: [PortConnection(portAId: stem, portBId: $0)]
            )
        }
    }
}
