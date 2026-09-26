import Foundation

struct TopologyDefinition: Codable, Equatable, Sendable {
    let revision: String
    let nodes: [TopologyNode]
    let trackSections: [TrackSection]
    let turnoutTopologies: [TurnoutTopology]
    let blocks: [BlockDefinition]
}

struct TopologyNode: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case joint
        case buffer
        case boundary
    }

    let id: String
    let name: String?
    let kind: Kind
}

struct TrackSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let nodeAId: String
    let nodeBId: String
    let lengthMm: Int?
}

struct TurnoutTopology: Codable, Equatable, Sendable {
    let turnoutId: String
    let ports: [TurnoutPort]
    let positions: [TurnoutTopologyPosition]
}

struct TurnoutPort: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let nodeId: String
}

struct TurnoutTopologyPosition: Codable, Equatable, Sendable {
    let positionId: String
    let connections: [PortConnection]
}

struct PortConnection: Codable, Equatable, Sendable {
    let portAId: String
    let portBId: String
}

struct BlockDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let trackSectionIds: [String]
    let turnoutIds: [String]?
}

struct LayoutPresentationDefinition: Codable, Equatable, Sendable {
    let revision: String
    let coordinateSystem: String
    let gridSpacing: Double
    let nodes: [LayoutNodePosition]
    let trackSections: [LayoutTrackPath]
    let turnouts: [LayoutTurnoutPresentation]
    let blocks: [LayoutBlockStyle]
}

struct LayoutPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct LayoutNodePosition: Codable, Equatable, Sendable {
    let nodeId: String
    let x: Double
    let y: Double
}

struct LayoutTrackPath: Codable, Equatable, Sendable {
    let trackSectionId: String
    let segments: [LayoutTrackSegment]
}

enum LayoutTrackSegment: Codable, Equatable, Sendable {
    case line(to: LayoutPoint)
    case cubic(control1: LayoutPoint, control2: LayoutPoint, to: LayoutPoint)

    private enum SegmentType: String, Codable {
        case line
        case cubic
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case control1
        case control2
        case to
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(SegmentType.self, forKey: .type) {
        case .line:
            self = .line(to: try container.decode(LayoutPoint.self, forKey: .to))
        case .cubic:
            self = .cubic(
                control1: try container.decode(LayoutPoint.self, forKey: .control1),
                control2: try container.decode(LayoutPoint.self, forKey: .control2),
                to: try container.decode(LayoutPoint.self, forKey: .to)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .line(let point):
            try container.encode(SegmentType.line, forKey: .type)
            try container.encode(point, forKey: .to)
        case .cubic(let control1, let control2, let point):
            try container.encode(SegmentType.cubic, forKey: .type)
            try container.encode(control1, forKey: .control1)
            try container.encode(control2, forKey: .control2)
            try container.encode(point, forKey: .to)
        }
    }
}

struct LayoutTurnoutPresentation: Codable, Equatable, Sendable {
    let turnoutId: String
    let x: Double
    let y: Double
    let rotationDegrees: Double
    let mirrored: Bool
}

struct LayoutBlockStyle: Codable, Equatable, Sendable {
    let blockId: String
    let color: String
    let opacity: Double
}

enum TurnoutKind: String, Codable, CaseIterable, Sendable {
    case simple
    case threeWay = "three_way"
    case doubleSlip = "double_slip"
    case singleSlip = "single_slip"
    case custom
}

enum AccessoryPosition: String, Codable, Sendable {
    case position1
    case position2
}

struct AccessoryEndpoint: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let linearAddress: Int
    let inverted: Bool
}

struct TurnoutPositionDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String?
    let endpoints: [String: AccessoryPosition]
}

struct TurnoutDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let kind: TurnoutKind
    let endpoints: [AccessoryEndpoint]
    let positions: [TurnoutPositionDefinition]
}

struct LayoutValidationResult: Codable, Equatable, Sendable {
    let valid: Bool
    let errors: [LayoutValidationDiagnostic]
    let warnings: [LayoutValidationDiagnostic]
}

struct LayoutValidationDiagnostic: Codable, Equatable, Sendable {
    let code: String
    let resourceType: String?
    let resourceId: String?
    let message: String
}

enum LayoutImportMode: String, Sendable {
    case merge
    case replace
}

struct LayoutArchive: Sendable {
    let data: Data
    let suggestedFilename: String
}
