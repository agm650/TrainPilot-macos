import SwiftUI

struct NetworkViewport: View {
    private let networkSize = CGSize(
        width: 1800,
        height: 1100
    )

    private let minimumZoom: CGFloat = 0.40
    private let maximumZoom: CGFloat = 2.50
    private let zoomStep: CGFloat = 0.10

    @State private var zoom: CGFloat = 1.0
    @GestureState private var gestureMagnification: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView([.horizontal, .vertical]) {
                NetworkPlaceholderCanvas()
                    .frame(
                        width: networkSize.width,
                        height: networkSize.height
                    )
                    .scaleEffect(
                        effectiveZoom,
                        anchor: .topLeading
                    )
                    // scaleEffect does not change layout size. This outer
                    // frame makes ScrollView aware of the scaled canvas.
                    .frame(
                        width: networkSize.width * effectiveZoom,
                        height: networkSize.height * effectiveZoom,
                        alignment: .topLeading
                    )
            }
            .simultaneousGesture(magnificationGesture)

            viewportLabel
                .padding(12)
                .allowsHitTesting(false)

            zoomControls
                .padding(12)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topTrailing
                )
        }
        .background(Color.black.opacity(0.18))
        .frame(
            minWidth: 300,
            maxWidth: .infinity,
            minHeight: 180,
            maxHeight: .infinity
        )
    }

    private var effectiveZoom: CGFloat {
        clampedZoom(zoom * gestureMagnification)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureMagnification) {
                value,
                state,
                _ in

                state = value
            }
            .onEnded { value in
                zoom = clampedZoom(zoom * value)
            }
    }

    private var viewportLabel: some View {
        HStack(spacing: 8) {
            Image(
                systemName:
                    "point.3.connected.trianglepath.dotted"
            )

            Text("PLAN DU RÉSEAU")
                .fontWeight(Font.Weight.bold)

            Text("• navigation X/Y")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .foregroundColor(SNCFPalette.gauge)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    SNCFPalette.panel.opacity(0.92)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    SNCFPalette.metal,
                    lineWidth: 1
                )
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            zoomButton(
                systemImage: "minus",
                help: "Dézoomer"
            ) {
                setZoom(zoom - zoomStep)
            }

            Button {
                setZoom(1.0)
            } label: {
                Text("\(Int((zoom * 100).rounded())) %")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 48)
            }
            .buttonStyle(.plain)
            .help("Réinitialiser le zoom à 100 %")

            zoomButton(
                systemImage: "plus",
                help: "Zoomer"
            ) {
                setZoom(zoom + zoomStep)
            }
        }
        .foregroundColor(SNCFPalette.gauge)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    SNCFPalette.panel.opacity(0.92)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    SNCFPalette.metal,
                    lineWidth: 1
                )
        )
    }

    private func zoomButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func setZoom(_ value: CGFloat) {
        zoom = clampedZoom(value)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumZoom), maximumZoom)
    }
}

private struct NetworkPlaceholderCanvas: View {
    private let gridStep: CGFloat = 80

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)

            grid
            demoTrack
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            Path { path in
                var x: CGFloat = 0

                while x <= geometry.size.width {
                    path.move(
                        to: CGPoint(x: x, y: 0)
                    )
                    path.addLine(
                        to: CGPoint(
                            x: x,
                            y: geometry.size.height
                        )
                    )
                    x += gridStep
                }

                var y: CGFloat = 0

                while y <= geometry.size.height {
                    path.move(
                        to: CGPoint(x: 0, y: y)
                    )
                    path.addLine(
                        to: CGPoint(
                            x: geometry.size.width,
                            y: y
                        )
                    )
                    y += gridStep
                }
            }
            .stroke(
                Color.secondary.opacity(0.10),
                lineWidth: 1
            )
        }
    }

    private var demoTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                let rect = CGRect(
                    x: width * 0.18,
                    y: height * 0.20,
                    width: width * 0.58,
                    height: height * 0.48
                )

                path.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(
                        width: 180,
                        height: 180
                    )
                )

                path.move(
                    to: CGPoint(
                        x: width * 0.34,
                        y: height * 0.44
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: width * 0.64,
                        y: height * 0.44
                    )
                )
            }
            .stroke(
                SNCFPalette.metal.opacity(0.8),
                style: StrokeStyle(
                    lineWidth: 5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            Text("Placeholder réseau")
                .font(.caption)
                .foregroundColor(.secondary)
                .position(
                    x: width * 0.47,
                    y: height * 0.78
                )
        }
    }
}
