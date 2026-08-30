import SwiftUI

struct DirectionSelector: View {
    let position: DirectionSelectorPosition
    let speed: Int
    let disabled: Bool
    let onSelect: (DirectionSelectorPosition) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("INVERSEUR")
                .font(.caption.bold())
                .foregroundColor(SNCFPalette.label)

            selectorButton(.forward)
            selectorButton(.neutral)
            selectorButton(.reverse)

            // Always reserve the same amount of space so switching between
            // 0 % and a moving state never changes the cab geometry.
            Text("Sens verrouillé en marche")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .opacity(speed > 0 ? 1 : 0)
                .frame(height: 28)
        }
        .padding(14)
        .frame(width: 150)
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
                .font(.title3.bold())
                .frame(width: 64, height: 32)
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
