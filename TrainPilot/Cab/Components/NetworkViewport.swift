//
//  NetworkViewport.swift
//  TrainPilot
//
//  Created by Luc Dandoy on 07/09/2026.
//


import SwiftUI

struct NetworkViewport: View {
    @State private var networkSize = CGSize(
        width: 1800,
        height: 1100
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView([.horizontal, .vertical]) {
                NetworkPlaceholderCanvas()
                    .frame(
                        width: networkSize.width,
                        height: networkSize.height
                    )
            }

            viewportLabel
                .padding(12)
                .allowsHitTesting(false)
        }
        .background(Color.black.opacity(0.18))
        .frame(
            minWidth: 300,
            maxWidth: .infinity,
            minHeight: 280,
            maxHeight: .infinity
        )
    }

    private var viewportLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")

            Text("PLAN DU RÉSEAU")
                .fontWeight(.bold)

            Text("• navigation X/Y")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .foregroundColor(SNCFPalette.gauge)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(SNCFPalette.panel.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(SNCFPalette.metal, lineWidth: 1)
        )
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
                    path.move(to: CGPoint(x: x, y: 0))
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
                    path.move(to: CGPoint(x: 0, y: y))
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
            let w = geometry.size.width
            let h = geometry.size.height

            Path { path in
                let rect = CGRect(
                    x: w * 0.18,
                    y: h * 0.20,
                    width: w * 0.58,
                    height: h * 0.48
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
                        x: w * 0.34,
                        y: h * 0.44
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: w * 0.64,
                        y: h * 0.44
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
                    x: w * 0.47,
                    y: h * 0.78
                )
        }
    }
}
