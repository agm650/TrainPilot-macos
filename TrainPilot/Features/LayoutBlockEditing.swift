import Foundation

enum LayoutBlockMember: Equatable {
    case trackSection(String)
    case turnout(String)
}

enum LayoutBlockValidationIssue: Equatable {
    case duplicateID(String)
    case invalidColor(blockID: String, color: String)
    case invalidOpacity(blockID: String, opacity: Double)
    case missingStyle(String)
    case unknownTrackSection(blockID: String, sectionID: String)
    case unknownTurnout(blockID: String, turnoutID: String)
}

struct LayoutBlockValidator {
    func validate(
        topology: TopologyDefinition,
        presentation: LayoutPresentationDefinition
    ) -> [LayoutBlockValidationIssue] {
        var issues: [LayoutBlockValidationIssue] = []
        let groups = Dictionary(grouping: topology.blocks, by: \.id)
        issues += groups.filter { $0.value.count > 1 }.map { .duplicateID($0.key) }

        let sectionIDs = Set(topology.trackSections.map(\.id))
        let turnoutIDs = Set(topology.turnoutTopologies.map(\.turnoutId))
        let styles = Dictionary(
            uniqueKeysWithValues: presentation.blocks.map { ($0.blockId, $0) }
        )
        let colorPattern = try? NSRegularExpression(
            pattern: "^#[0-9A-Fa-f]{6}$"
        )

        for block in topology.blocks {
            guard let style = styles[block.id] else {
                issues.append(.missingStyle(block.id))
                continue
            }
            let colorRange = NSRange(
                style.color.startIndex..<style.color.endIndex,
                in: style.color
            )
            if colorPattern?.firstMatch(
                in: style.color,
                range: colorRange
            ) == nil {
                issues.append(.invalidColor(blockID: block.id, color: style.color))
            }
            if !(0...1).contains(style.opacity) {
                issues.append(
                    .invalidOpacity(blockID: block.id, opacity: style.opacity)
                )
            }
            for sectionID in block.trackSectionIds where !sectionIDs.contains(sectionID) {
                issues.append(
                    .unknownTrackSection(blockID: block.id, sectionID: sectionID)
                )
            }
            for turnoutID in block.turnoutIds ?? [] where !turnoutIDs.contains(turnoutID) {
                issues.append(
                    .unknownTurnout(blockID: block.id, turnoutID: turnoutID)
                )
            }
        }
        return issues
    }
}

extension LayoutEditorController {
    @discardableResult
    func addBlock(
        id: String = UUID().uuidString,
        name: String = "Nouveau block",
        color: String = "#33AADD",
        opacity: Double = 0.4
    ) -> String {
        let block = BlockDefinition(
            id: id,
            name: name,
            trackSectionIds: [],
            turnoutIds: []
        )
        let style = LayoutBlockStyle(
            blockId: id,
            color: color,
            opacity: min(max(opacity, 0), 1)
        )
        performMutation {
            document.replaceSnapshot(
                LayoutSnapshot(
                    topology: document.topology.replacing(
                        blocks: document.topology.blocks + [block]
                    ),
                    presentation: document.presentation.replacing(
                        blocks: document.presentation.blocks + [style]
                    )
                )
            )
        }
        select(.block(id))
        return id
    }

    func updateBlockStyle(
        blockID: String,
        color: String,
        opacity: Double
    ) throws {
        guard document.presentation.blocks.contains(where: {
            $0.blockId == blockID
        }) else {
            throw LayoutEditError.missingResource(blockID)
        }
        let styles = document.presentation.blocks.map { style in
            style.blockId == blockID
                ? LayoutBlockStyle(
                    blockId: blockID,
                    color: color,
                    opacity: min(max(opacity, 0), 1)
                )
                : style
        }
        performMutation {
            document.replacePresentation(document.presentation.replacing(blocks: styles))
        }
    }

    func add(_ member: LayoutBlockMember, toBlock blockID: String) throws {
        try updateMembership(member, blockID: blockID, shouldContain: true)
    }

    func remove(_ member: LayoutBlockMember, fromBlock blockID: String) throws {
        try updateMembership(member, blockID: blockID, shouldContain: false)
    }

    private func updateMembership(
        _ member: LayoutBlockMember,
        blockID: String,
        shouldContain: Bool
    ) throws {
        guard let blockIndex = document.topology.blocks.firstIndex(where: {
            $0.id == blockID
        }) else {
            throw LayoutEditError.missingResource(blockID)
        }
        switch member {
        case .trackSection(let id):
            guard document.topology.trackSections.contains(where: { $0.id == id }) else {
                throw LayoutEditError.missingResource(id)
            }
        case .turnout(let id):
            guard document.topology.turnoutTopologies.contains(where: {
                $0.turnoutId == id
            }) else {
                throw LayoutEditError.missingResource(id)
            }
        }

        var blocks = document.topology.blocks
        let block = blocks[blockIndex]
        var sectionIDs = block.trackSectionIds
        var turnoutIDs = block.turnoutIds ?? []

        switch member {
        case .trackSection(let id):
            sectionIDs = updatedMembership(
                sectionIDs,
                id: id,
                shouldContain: shouldContain
            )
        case .turnout(let id):
            turnoutIDs = updatedMembership(
                turnoutIDs,
                id: id,
                shouldContain: shouldContain
            )
        }

        blocks[blockIndex] = BlockDefinition(
            id: block.id,
            name: block.name,
            trackSectionIds: sectionIDs,
            turnoutIds: turnoutIDs
        )
        performMutation {
            document.replaceTopology(document.topology.replacing(blocks: blocks))
        }
    }

    private func updatedMembership(
        _ ids: [String],
        id: String,
        shouldContain: Bool
    ) -> [String] {
        if shouldContain {
            return ids.contains(id) ? ids : ids + [id]
        }
        return ids.filter { $0 != id }
    }
}
