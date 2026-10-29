import SwiftUI

struct LayoutTurnoutConfigurationView: View {
    @ObservedObject var controller: LayoutEditorController
    let definition: TurnoutDefinition
    @State private var name: String
    @State private var addresses: [String: String]
    @State private var inversions: [String: Bool]
    @State private var mappings: [String: [String: AccessoryPosition]]
    @State private var message: String?

    init(controller: LayoutEditorController, definition: TurnoutDefinition) {
        self.controller = controller
        self.definition = definition
        _name = State(initialValue: definition.name)
        _addresses = State(initialValue: Dictionary(uniqueKeysWithValues:
            definition.endpoints.map { ($0.id, String($0.linearAddress)) }))
        _inversions = State(initialValue: Dictionary(uniqueKeysWithValues:
            definition.endpoints.map { ($0.id, $0.inverted) }))
        _mappings = State(initialValue: Dictionary(uniqueKeysWithValues:
            definition.positions.map { ($0.id, $0.endpoints) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration de l’appareil").font(.headline)
            TextField("Nom", text: $name)
                .textFieldStyle(.roundedBorder)
            ForEach(definition.endpoints) { endpoint in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Moteur \(endpoint.id.uppercased())").font(.subheadline)
                    TextField("Adresse DCC (1–2040)", text: Binding(
                        get: { addresses[endpoint.id] ?? "" },
                        set: { addresses[endpoint.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Toggle("Inverser les commandes", isOn: Binding(
                        get: { inversions[endpoint.id] ?? false },
                        set: { inversions[endpoint.id] = $0 }
                    ))
                }
            }
            Divider()
            Text("Positions et commandes").font(.headline)
            Text("L’inversion échange les commandes 1 et 2 du moteur concerné.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(definition.positions) { position in
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.label ?? positionTitle(position.id)).fontWeight(.semibold)
                    ForEach(definition.endpoints) { endpoint in
                        Picker("Moteur \(endpoint.id.uppercased())", selection: Binding(
                            get: { mappings[position.id]?[endpoint.id] ?? .position1 },
                            set: { mappings[position.id, default: [:]][endpoint.id] = $0 }
                        )) {
                            Text("Position 1").tag(AccessoryPosition.position1)
                            Text("Position 2").tag(AccessoryPosition.position2)
                        }
                    }
                }
            }
            HStack {
                Button("Appliquer") { apply() }
                Button("Réinitialiser") { reset() }
            }
            Text("Appliquez avant d’enregistrer ou de publier.")
                .font(.caption).foregroundColor(.secondary)
            if let message {
                Text(message).font(.caption)
            }
        }
        .onChange(of: definition) { _ in reset() }
    }

    private func positionTitle(_ id: String) -> String {
        switch id {
        case "straight": return "Directe"
        case "diverging": return "Déviée"
        case "left": return "Gauche"
        case "right": return "Droite"
        case "crossed": return "Croisée"
        default: return id
        }
    }

    private func reset() {
        name = definition.name
        addresses = Dictionary(uniqueKeysWithValues:
            definition.endpoints.map { ($0.id, String($0.linearAddress)) })
        inversions = Dictionary(uniqueKeysWithValues:
            definition.endpoints.map { ($0.id, $0.inverted) })
        mappings = Dictionary(uniqueKeysWithValues:
            definition.positions.map { ($0.id, $0.endpoints) })
        message = nil
    }

    private func apply() {
        do {
            let endpoints = try definition.endpoints.map { endpoint in
                guard let address = Int((addresses[endpoint.id] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw TurnoutConfigurationError.invalid("Renseignez une adresse entière pour chaque moteur.")
                }
                return AccessoryEndpoint(
                    id: endpoint.id, linearAddress: address,
                    inverted: inversions[endpoint.id] ?? false
                )
            }
            let positions = definition.positions.map { position in
                TurnoutPositionDefinition(
                    id: position.id, label: position.label,
                    endpoints: mappings[position.id] ?? [:]
                )
            }
            try controller.configureTurnout(
                id: definition.id, name: name,
                endpoints: endpoints, positions: positions
            )
            message = "Configuration appliquée au document."
        } catch {
            message = error.localizedDescription
        }
    }
}
