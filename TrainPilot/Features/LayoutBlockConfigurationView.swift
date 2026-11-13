import SwiftUI

struct LayoutBlockConfigurationView: View {
    @ObservedObject var controller: LayoutEditorController
    @ObservedObject var document: LayoutEditorDocument
    let block: BlockDefinition
    @State private var name = ""
    @State private var source = "z21-rbus"
    @State private var address = ""
    @State private var input = "1"
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canton").font(.headline)
            Text("\(block.trackSectionIds.count) sections de voie")
            TextField("Nom du canton", text: $name)
            Text("Couleur du canton").font(.caption)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                ForEach(LayoutBlockPaletteColor.all) { color in
                    Button {
                        do {
                            try controller.chooseBlockColor(blockID: block.id, hex: color.hex)
                            messageIsError = false
                            message = "Couleur appliquée."
                        } catch {
                            messageIsError = true
                            message = error.localizedDescription
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: color.hex))
                            .frame(height: 26)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(2)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .opacity(selectedColor == color.hex ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel(Text(color.name))
                    .accessibilityValue(selectedColor == color.hex ? Text("Sélectionnée") : Text("Non sélectionnée"))
                }
            }
            Text("Couleur appliquée immédiatement au plan. Rouge réservé à l’occupation.")
                .font(.caption).foregroundColor(.secondary)
            Text("Source de détection").font(.caption)
            Picker("Source de détection", selection: $source) {
                Text("Z21 / R-BUS").tag("z21-rbus")
                if source != "z21-rbus" {
                    Text("Source importée : " + source).tag(source)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text(source == "z21-rbus" ? "Adresse du détecteur" : "Identifiant du contact").font(.caption)
            TextField("Adresse", text: $address)
            if source == "z21-rbus" {
                Text("Numéro de l’entrée").font(.caption)
                TextField("Entrée (1–8)", text: $input)
                Text("Une adresse R-BUS correspond à 8 entrées.")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Button("Appliquer") {
                    do {
                        guard source == "z21-rbus",
                              let detector = Int(address.trimmingCharacters(in: .whitespacesAndNewlines)),
                              let entry = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                            throw TurnoutConfigurationError.invalid("Renseignez une adresse de détecteur et un numéro d’entrée valides.")
                        }
                        let contact = try RBusContactAddress(detector: detector, input: entry).globalAddress()
                        try controller.configureBlock(id: block.id, name: name, source: source, address: String(contact))
                        messageIsError = false
                        message = "Configuration appliquée."
                    } catch {
                        messageIsError = true
                        message = error.localizedDescription
                    }
                }
                .disabled(source != "z21-rbus")
                Button("Détruire", role: .destructive) {
                    do {
                        controller.select(.block(block.id))
                        try controller.deleteSelection()
                    } catch {
                        messageIsError = true
                        message = error.localizedDescription
                    }
                }
                .help("Supprimer le canton en conservant ses voies et aiguillages. Cette action peut être annulée.")
            }
            Text("Appliquez avant d’enregistrer ou de publier.")
                .font(.caption).foregroundColor(.secondary)
            Text(message ?? "Configuration appliquée.")
                .font(.caption)
                .foregroundColor(messageIsError ? .red : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(message == nil ? 0 : 1)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { reload() }
        .onChange(of: document.topology) { _ in reload() }
    }

    private var selectedColor: String {
        LayoutBlockPaletteColor.displayHex(document.presentation.blocks.first { $0.blockId == block.id }?.color)
    }

    private func reload() {
        name = block.name
        let mapping = document.topology.feedbackMappings?.first { $0.blockId == block.id }
        let sensor = document.topology.occupancySensorMappings?.first { $0.blockId == block.id }
        source = mapping?.provider ?? sensor?.providerId ?? "z21-rbus"
        let rawAddress = mapping.map { String($0.address) } ?? sensor?.sensorId ?? ""
        if source == "z21-rbus", let value = Int(rawAddress),
           let contact = RBusContactAddress(globalAddress: value) {
            address = String(contact.detector)
            input = String(contact.input)
        } else {
            address = rawAddress
            input = "1"
        }
    }
}
