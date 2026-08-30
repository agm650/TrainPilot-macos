import SwiftUI

struct SpeedGauge: View {
    let requested: Int
    let confirmed: Int?

    var body: some View {
        ZStack {
            Circle()
                .fill(SNCFPalette.panelRaised)

            Circle()
                .stroke(SNCFPalette.metal, lineWidth: 6)

            Circle()
                .stroke(SNCFPalette.gauge.opacity(0.25), lineWidth: 1)
                .padding(12)

            VStack(spacing: 2) {
                Text("\(requested)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(SNCFPalette.gauge)

                Text("%")
                    .font(.title3.bold())
                    .foregroundColor(SNCFPalette.label)

                if let confirmed, confirmed != requested {
                    Text("confirmé \(confirmed) %")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(SNCFPalette.orange)
                } else if confirmed != nil {
                    Text("confirmé")
                        .font(.caption)
                        .foregroundColor(SNCFPalette.green)
                } else {
                    Text("état inconnu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Vitesse demandée \(requested) pour cent")
    }
}
