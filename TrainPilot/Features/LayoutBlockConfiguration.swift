import Foundation

struct RBusContactAddress: Equatable {
    let detector: Int
    let input: Int

    init(detector: Int, input: Int) {
        self.detector = detector
        self.input = input
    }

    init?(globalAddress: Int) {
        guard globalAddress > 0 else { return nil }
        detector = (globalAddress - 1) / 8 + 1
        input = (globalAddress - 1) % 8 + 1
    }

    func globalAddress() throws -> Int {
        guard detector > 0, (1...8).contains(input) else {
            throw TurnoutConfigurationError.invalid("Renseignez une adresse de détecteur positive et une entrée de 1 à 8.")
        }
        let (base, overflow) = (detector - 1).multipliedReportingOverflow(by: 8)
        let (address, additionOverflow) = base.addingReportingOverflow(input)
        guard !overflow, !additionOverflow else {
            throw TurnoutConfigurationError.invalid("L’adresse du détecteur est trop grande.")
        }
        return address
    }
}

extension LayoutEditorController {
    func createBlockFromSelection() throws {
        let tracks = selectedElements.compactMap { selection -> String? in
            if case .trackSection(let id) = selection { return id }
            return nil
        }.sorted()
        guard !tracks.isEmpty, tracks.count == selectedElements.count else {
            throw TurnoutConfigurationError.invalid("Sélectionnez uniquement les sections de voie du canton.")
        }
        guard !document.topology.blocks.contains(where: { !Set($0.trackSectionIds).isDisjoint(with: tracks) }) else {
            throw TurnoutConfigurationError.invalid("Une section sélectionnée appartient déjà à un canton.")
        }
        let sections = document.topology.trackSections.filter { tracks.contains($0.id) }
        guard let first = sections.first else { return }
        var connected = Set([first.nodeAId, first.nodeBId])
        var remaining = Array(sections.dropFirst())
        while let index = remaining.firstIndex(where: { connected.contains($0.nodeAId) || connected.contains($0.nodeBId) }) {
            let section = remaining.remove(at: index)
            connected.formUnion([section.nodeAId, section.nodeBId])
        }
        guard remaining.isEmpty else {
            throw TurnoutConfigurationError.invalid("Les sections du canton doivent être reliées entre elles.")
        }
        let id = UUID().uuidString
        let block = BlockDefinition(id: id, name: "Nouveau canton", trackSectionIds: tracks, turnoutIds: [])
        let style = LayoutBlockStyle(blockId: id, color: "#33AADD", opacity: 0.6)
        performMutation {
            document.replaceSnapshot(LayoutSnapshot(
                topology: document.topology.replacing(blocks: document.topology.blocks + [block]),
                presentation: document.presentation.replacing(blocks: document.presentation.blocks + [style])
            ))
        }
        select(.block(id))
    }

    func configureBlock(id: String, name: String, source: String, address: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !source.isEmpty, let number = Int(address), number > 0 else {
            throw TurnoutConfigurationError.invalid("Renseignez un nom, une source et une adresse de contact entière positive.")
        }
        let topology = document.topology
        let mappingCount = (topology.feedbackMappings ?? []).filter { $0.blockId == id }.count
            + (topology.occupancySensorMappings ?? []).filter { $0.blockId == id }.count
        guard mappingCount <= 1 else {
            throw TurnoutConfigurationError.invalid("Ce canton possède plusieurs détecteurs. Cette version du formulaire ne modifie que les cantons à un seul contact.")
        }
        guard topology.blocks.contains(where: { $0.id == id }) else { throw LayoutEditError.missingResource(id) }
        let conflict = topology.feedbackMappings?.first {
            $0.blockId != id && $0.provider == source && $0.address == number
        }?.blockId ?? topology.occupancySensorMappings?.first {
            $0.blockId != id && $0.providerId == source && $0.sensorId == String(number)
        }?.blockId
        if let conflict {
            let otherName = topology.blocks.first { $0.id == conflict }?.name ?? conflict
            if source == "z21-rbus", let contact = RBusContactAddress(globalAddress: number) {
                throw TurnoutConfigurationError.invalid(
                    "Le détecteur \(contact.detector), entrée \(contact.input), est déjà utilisé par le canton « \(otherName) »."
                )
            }
            throw TurnoutConfigurationError.invalid("Ce contact est déjà associé au canton « \(otherName) ».")
        }
        var updated = topology.replacing(blocks: topology.blocks.map {
            $0.id == id ? BlockDefinition(id: id, name: name, trackSectionIds: $0.trackSectionIds, turnoutIds: $0.turnoutIds) : $0
        })
        // Numeric mappings are migrated by the server to its generic provider/sensor model.
        updated.feedbackMappings = (topology.feedbackMappings ?? []).filter { $0.blockId != id } + [
            LayoutFeedbackMapping(provider: source, address: number, blockId: id)
        ]
        updated.occupancySensorMappings = (topology.occupancySensorMappings ?? []).filter { $0.blockId != id }
        performMutation { document.replaceTopology(updated) }
    }
}

extension TopologyDefinition {
    func removingDetection(for blockID: String) -> TopologyDefinition {
        var copy = self
        copy.feedbackMappings = feedbackMappings?.filter { $0.blockId != blockID }
        copy.occupancySensorMappings = occupancySensorMappings?.filter { $0.blockId != blockID }
        return copy
    }
}
