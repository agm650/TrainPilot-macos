import SwiftUI

struct LayoutCanvas: View {
    let topology: TopologyDefinition
    let presentation: LayoutPresentationDefinition
    let mode: LayoutInteractionMode
    var runtime: TopologyRuntimeState = .empty
    var onTurnoutSelected: ((String) -> Void)?
    var onEditorGestureEnded: ((
        LayoutPoint,
        LayoutPoint,
        LayoutViewportTransform
    ) -> Void)?

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
                    showsGrid: showsGrid,
                    runtime: runtime
                )
                .contentShape(Rectangle())
                .gesture(primaryDragGesture)
                .simultaneousGesture(magnificationGesture(in: geometry.size))

                turnoutHitTargets(in: geometry.size)

                LayoutCanvasControls(
                    zoom: transform.zoom,
                    showsGrid: $showsGrid,
                    snapToGrid: $snapToGrid,
                    showsSnapControl: mode != .operationalReadOnly,
                    zoomOut: { setZoom(transform.zoom - 0.25, in: geometry.size) },
                    resetZoom: { setZoom(1, in: geometry.size) },
                    zoomIn: { setZoom(transform.zoom + 0.25, in: geometry.size) }
                )
                .padding(12)
            }
            .background(Color.black.opacity(0.12))
        }
    }

    @ViewBuilder
    private func turnoutHitTargets(in size: CGSize) -> some View {
        if mode == .operationalReadOnly, let onTurnoutSelected {
            let viewport = effectiveTransform(in: size)
            ForEach(presentation.turnouts, id: \.turnoutId) { turnout in
                Button {
                    onTurnoutSelected(turnout.turnoutId)
                } label: {
                    Circle()
                        .fill(Color.clear)
                        .contentShape(Circle())
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .position(
                    viewport.canvasPoint(
                        for: LayoutPoint(x: turnout.x, y: turnout.y)
                    )
                )
                .accessibilityLabel("Aiguillage \(turnout.turnoutId)")
            }
        }
    }

    private var primaryDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard onEditorGestureEnded == nil else { return }
                transform = panAtGestureStart.pannedBy(
                    x: value.translation.width,
                    y: value.translation.height
                )
            }
            .onEnded { value in
                if let onEditorGestureEnded {
                    onEditorGestureEnded(
                        transform.layoutPoint(for: value.startLocation),
                        transform.layoutPoint(for: value.location),
                        transform
                    )
                } else {
                    panAtGestureStart = transform
                }
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
    let showsSnapControl: Bool
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

            if showsSnapControl {
                Toggle(isOn: $snapToGrid) {
                    Image(systemName: "dot.squareshape.split.2x2")
                }
                .toggleStyle(.button)
                .help("Activer ou désactiver l’alignement sur la grille")
                .accessibilityLabel("Alignement sur la grille")
            }

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
