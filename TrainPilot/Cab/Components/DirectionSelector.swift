import SwiftUI

struct DirectionSelector: View {
    let position: DirectionSelectorPosition
    let speed: Int
    let disabled: Bool
    let compact: Bool
    let onSelect: (DirectionSelectorPosition) -> Void

    init(
        position: DirectionSelectorPosition,
        speed: Int,
        disabled: Bool,
        compact: Bool = false,
        onSelect: @escaping (DirectionSelectorPosition) -> Void
    ) {
        self.position = position
        self.speed = speed
        self.disabled = disabled
        self.compact = compact
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            Text("INVERSEUR")
                .font(.caption.bold())
                .foregroundColor(SNCFPalette.label)

            selectorButton(.forward)
            selectorButton(.neutral)
            selectorButton(.reverse)

            // Keep a reserved status area so the component never changes
            // geometry when the locomotive starts or stops.
            Text("Sens verrouillé en marche")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .opacity(speed > 0 ? 1 : 0)
                .frame(height: compact ? 18 : 28)
        }
        .padding(compact ? 10 : 14)
        .frame(
            width: compact ? 138 : 150,
            height: compact ? 174 : nil
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SNCFPalette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SNCFPalette.metal, lineWidth: 2)
                )
        )
    }

    private func selectorButton(
        _ target: DirectionSelectorPosition
    ) -> some View {
        let selected = position == target
        let directionChangeBlocked =
            speed > 0 &&
            target != .neutral &&
            target != position

        return Button {
            onSelect(target)
        } label: {
            Text(target.label)
                .font(compact ? .body.bold() : .title3.bold())
                .frame(
                    width: compact ? 58 : 64,
                    height: compact ? 28 : 32
                )
        }
        .buttonStyle(.plain)
        .foregroundColor(
            selected
            ? Color.black
            : SNCFPalette.gauge
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    selected
                    ? SNCFPalette.label
                    : SNCFPalette.panel
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SNCFPalette.metal, lineWidth: 1)
        )
        .disabled(disabled || directionChangeBlocked)
    }
}
