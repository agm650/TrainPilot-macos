import SwiftUI

struct FunctionPanel: View {
    @ObservedObject var session: DrivingSession
    let functionCount: Int
    let columnCount: Int
    let disabled: Bool
    let onToggle: (Int) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 54),
                spacing: 8
            ),
            count: max(1, columnCount)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FONCTIONS")
                .font(.caption.bold())
                .foregroundColor(SNCFPalette.label)

            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(
                        0..<max(functionCount, 0),
                        id: \.self
                    ) { function in
                        FunctionControl(
                            session: session, function: function,
                            disabled: disabled, onToggle: { onToggle(function) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SNCFPalette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            SNCFPalette.metal,
                            lineWidth: 2
                        )
                )
        )
    }
}

private struct FunctionControl: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var session: DrivingSession
    let function: Int
    let disabled: Bool
    let onToggle: () -> Void
    @State private var pressToken: UUID?
    @State private var gestureStarted = false
    @GestureState private var dragging = false

    private var momentary: Bool { session.locomotive.isMomentary(function) }
    private var active: Bool { session.functionStates[function] ?? false }

    var body: some View {
        Group {
            if momentary {
                label
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragging) { _, state, _ in state = true }
                            .onChanged { _ in
                                guard !gestureStarted else { return }
                                gestureStarted = true
                                press()
                            }
                            .onEnded { _ in
                                release()
                                gestureStarted = false
                            }
                    )
                    .onChange(of: dragging) { held in
                        if !held {
                            release()
                            gestureStarted = false
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { pressToken == nil ? press() : release() }
                    .accessibilityAction(named: Text("Activer")) { press() }
                    .accessibilityAction(named: Text("Relâcher")) { release() }
            } else {
                Button(action: onToggle) { label }
                    .buttonStyle(.plain)
            }
        }
        .foregroundColor(SNCFPalette.gauge)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? SNCFPalette.metal : SNCFPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SNCFPalette.metal, lineWidth: 1)
        )
        .disabled(disabled)
        .help(momentary ? "Maintenir pour activer, relâcher pour arrêter" : "Cliquer pour activer ou désactiver")
        .accessibilityLabel("Fonction F\(function)")
        .accessibilityValue(active ? "Activée" : "Désactivée")
        .onChange(of: disabled) { value in if value { release() } }
        .onChange(of: session.locomotive.id) { _ in release() }
        .onChange(of: momentary) { _ in release() }
        .onDisappear { release() }
    }

    private var label: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text("F\(function)").font(.callout.bold())
                if momentary {
                    Image(systemName: "hand.point.up.left.fill").font(.caption2)
                }
            }
            Circle()
                .fill(active ? SNCFPalette.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func press() {
        guard !disabled, pressToken == nil else { return }
        pressToken = appModel.pressMomentaryFunction(
            locomotiveID: session.locomotive.id, function: function
        )
    }

    private func release() {
        if let pressToken { appModel.momentaryFunctions.release(pressToken) }
        pressToken = nil
    }
}
