import SwiftUI

struct LayoutCanvas: View {
    let topology: TopologyDefinition
    let presentation: LayoutPresentationDefinition
    let mode: TopologyRendererMode

    @AppStorage("layoutEditorShowsGrid") private var showsGrid = true
    @AppStorage("layoutEditorSnapToGrid") private var snapToGrid = true
    @State private var transform = LayoutViewportTransform()
    @State private var panAtGestureStart = LayoutViewportTransform()
    @GestureState private var magnification = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                TopologyRenderer(
                    plan: TopologyRenderPlan(
                        topology: topology,
                        presentation: presentation
                    ),
                    transform: effectiveTransform(in: geometry.size),
                    mode: mode,
                    gridSpacing: presentation.gridSpacing,
                    showsGrid: showsGrid
                )
                .contentShape(Rectangle())
                .gesture(panGesture)
                .simultaneousGesture(magnificationGesture(in: geometry.size))

                LayoutCanvasControls(
                    zoom: transform.zoom,
                    showsGrid: $showsGrid,
                    snapToGrid: $snapToGrid,
                    zoomOut: { setZoom(transform.zoom - 0.25, in: geometry.size) },
                    resetZoom: { setZoom(1, in: geometry.size) },
                    zoomIn: { setZoom(transform.zoom + 0.25, in: geometry.size) }
                )
                .padding(12)
            }
            .background(Color.black.opacity(0.12))
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                transform = LayoutViewportTransform(
                    zoom: panAtGestureStart.zoom,
                    panX: panAtGestureStart.panX + value.translation.width,
                    panY: panAtGestureStart.panY + value.translation.height
                )
            }
            .onEnded { _ in
                panAtGestureStart = transform
            }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                setZoom(transform.zoom * value, in: size)
            }
    }

    private func effectiveTransform(in size: CGSize) -> LayoutViewportTransform {
        transform.zoomed(
            to: transform.zoom * magnification,
            around: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    private func setZoom(_ zoom: Double, in size: CGSize) {
        transform = transform.zoomed(
            to: zoom,
            around: CGPoint(x: size.width / 2, y: size.height / 2)
        )
        panAtGestureStart = transform
    }
}

private struct LayoutCanvasControls: View {
    let zoom: Double
    @Binding var showsGrid: Bool
    @Binding var snapToGrid: Bool
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let zoomIn: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $showsGrid) {
                Image(systemName: "grid")
            }
            .toggleStyle(.button)
            .help("Afficher ou masquer la grille")
            .accessibilityLabel("Afficher la grille")

            Toggle(isOn: $snapToGrid) {
                Image(systemName: "dot.squareshape.split.2x2")
            }
            .toggleStyle(.button)
            .help("Activer ou désactiver l’alignement sur la grille")
            .accessibilityLabel("Alignement sur la grille")

            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .accessibilityLabel("Dézoomer")

            Button(action: resetZoom) {
                Text("\(Int((zoom * 100).rounded())) %")
                    .monospacedDigit()
                    .frame(minWidth: 52)
            }
            .accessibilityLabel("Réinitialiser le zoom à 100 pour cent")

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .accessibilityLabel("Zoomer")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
