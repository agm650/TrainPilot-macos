import SwiftUI

struct LayoutTilePalette: View {
    @ObservedObject var controller: LayoutEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bibliothèque TCO").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LayoutTileProfile.allCases) { profile in
                        Button {
                            controller.selectTile(profile)
                        } label: {
                            VStack(spacing: 4) {
                                LayoutTileSymbol(profile: profile, rotationSteps: controller.tileRotationSteps)
                                    .frame(width: 40, height: 40)
                                Text(profile.title).font(.caption)
                            }
                            .frame(width: 95, height: 64)
                            .background(
                                controller.tool == .tile && controller.tileProfile == profile
                                    ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Poser : " + profile.title)
                        .accessibilityLabel(profile.title)
                        .accessibilityAddTraits(
                            controller.tool == .tile && controller.tileProfile == profile ? .isSelected : []
                        )
                    }
                }
            }
            HStack {
                Button {
                    controller.tileRotationSteps = (controller.tileRotationSteps + 1) % 8
                } label: {
                    Label("Tourner 45°", systemImage: "rotate.right")
                }
                Text("Choisissez une pièce, puis cliquez dans une case.").font(.caption)
                Spacer()
            }
            Text(controller.tilePlacementMessage ?? "Une pièce par case · raccordement automatique")
                .font(.caption)
                .foregroundColor(controller.tilePlacementMessage == nil ? .secondary : .orange)
                .frame(height: 18, alignment: .leading)
        }
        .padding(10)
    }
}

private struct LayoutTileSymbol: View {
    let profile: LayoutTileProfile
    let rotationSteps: Int

    var body: some View {
        Canvas { context, size in
            func point(_ value: LayoutPoint) -> CGPoint {
                let rotated = profile.point(value, rotationSteps: rotationSteps)
                return CGPoint(x: rotated.x * size.width, y: rotated.y * size.height)
            }
            var path = Path()
            let ports = profile.ports
            if profile.turnoutKind != nil {
                for port in ports {
                    path.move(to: point(LayoutPoint(x: 0.5, y: 0.5)))
                    path.addLine(to: point(port))
                }
            } else {
                path.move(to: point(ports[0]))
                if profile == .curve {
                    path.addCurve(
                        to: point(ports[1]),
                        control1: point(LayoutPoint(x: 0.2761423749, y: 0.5)),
                        control2: point(LayoutPoint(x: 0.5, y: 0.2761423749))
                    )
                } else {
                    path.addLine(to: point(ports[1]))
                }
            }
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .background(Color.secondary.opacity(0.08))
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
