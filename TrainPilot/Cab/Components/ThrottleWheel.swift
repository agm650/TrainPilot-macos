import SwiftUI

struct ThrottleWheelMath {
    static let startAngle = 140.0
    static let sweepAngle = 260.0

    static func angle(for percentage: Int) -> Double {
        startAngle + (Double(min(max(percentage, 0), 100)) / 100.0) * sweepAngle
    }

    static func percentage(for point: CGPoint, in size: CGSize) -> Int {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        if degrees <= 40 {
            degrees += 360
        } else if degrees < startAngle {
            let distanceToStart = startAngle - degrees
            let distanceToEnd = abs(degrees + 360 - (startAngle + sweepAngle))
            degrees = distanceToStart < distanceToEnd ? startAngle : startAngle + sweepAngle
        }

        let clamped = min(max(degrees, startAngle), startAngle + sweepAngle)
        let normalized = (clamped - startAngle) / sweepAngle
        return Int((normalized * 100).rounded())
    }
}

struct ThrottleWheel: View {
    let value: Int
    let confirmedValue: Int?
    let enabled: Bool
    let onChange: (Int) -> Void
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let dimension = min(size.width, size.height)
            let radius = dimension * 0.36
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                Circle()
                    .fill(SNCFPalette.panelRaised)
                    .frame(width: dimension * 0.78, height: dimension * 0.78)

                Circle()
                    .stroke(SNCFPalette.metal, lineWidth: 16)
                    .frame(width: dimension * 0.68, height: dimension * 0.68)

                ForEach(Array(stride(from: 0, through: 100, by: 10)), id: \.self) { tick in
                    tickMark(tick, center: center, radius: radius)
                }

                if let confirmedValue {
                    confirmedMarker(confirmedValue, center: center, radius: radius * 0.90)
                }

                handle(value, center: center, radius: radius, dimension: dimension)

                VStack(spacing: 2) {
                    Text("\(value) %")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundColor(SNCFPalette.gauge)

                    Text(enabled ? "TRACTION" : "NEUTRE")
                        .font(.caption.bold())
                        .foregroundColor(enabled ? SNCFPalette.label : .secondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        onChange(
                            ThrottleWheelMath.percentage(
                                for: gesture.location,
                                in: size
                            )
                        )
                    }
                    .onEnded { _ in
                        guard enabled else { return }
                        onCommit()
                    }
            )
            .opacity(enabled ? 1 : 0.62)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Grande roue de vitesse")
        .accessibilityValue("\(value) pour cent")
    }

    private func handle(
        _ percentage: Int,
        center: CGPoint,
        radius: CGFloat,
        dimension: CGFloat
    ) -> some View {
        let angle = ThrottleWheelMath.angle(for: percentage)
        let radians = angle * .pi / 180
        let x = center.x + cos(radians) * radius
        let y = center.y + sin(radians) * radius

        return ZStack {
            Path { path in
                path.move(to: center)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            .stroke(SNCFPalette.gauge.opacity(0.6), lineWidth: 5)

            Circle()
                .fill(SNCFPalette.label)
                .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 3))
                .frame(width: dimension * 0.10, height: dimension * 0.10)
                .position(x: x, y: y)
                .shadow(radius: 3)
        }
    }

    private func confirmedMarker(
        _ percentage: Int,
        center: CGPoint,
        radius: CGFloat
    ) -> some View {
        let angle = ThrottleWheelMath.angle(for: percentage)
        let radians = angle * .pi / 180
        let x = center.x + cos(radians) * radius
        let y = center.y + sin(radians) * radius

        return Circle()
            .fill(SNCFPalette.green)
            .frame(width: 9, height: 9)
            .position(x: x, y: y)
    }

    private func tickMark(
        _ percentage: Int,
        center: CGPoint,
        radius: CGFloat
    ) -> some View {
        let angle = ThrottleWheelMath.angle(for: percentage)
        let radians = angle * .pi / 180
        let inner = radius * 0.80
        let outer = radius * 0.92

        let start = CGPoint(
            x: center.x + cos(radians) * inner,
            y: center.y + sin(radians) * inner
        )
        let end = CGPoint(
            x: center.x + cos(radians) * outer,
            y: center.y + sin(radians) * outer
        )

        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            percentage % 20 == 0 ? SNCFPalette.label : SNCFPalette.gauge.opacity(0.55),
            lineWidth: percentage % 20 == 0 ? 3 : 1
        )
    }
}
