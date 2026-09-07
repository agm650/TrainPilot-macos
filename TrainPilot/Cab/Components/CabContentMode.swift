//
//  CabContentMode.swift
//  TrainPilot
//
//  Created by Luc Dandoy on 07/09/2026.
//


import SwiftUI

enum CabContentMode: String, CaseIterable, Identifiable {
    case network
    case video
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .network:
            return "Réseau"
        case .video:
            return "Vidéo"
        case .split:
            return "Réseau + vidéo"
        }
    }
}

struct CabContentArea: View {
    let mode: CabContentMode

    var body: some View {
        Group {
            switch mode {
            case .network:
                NetworkViewport()

            case .video:
                VideoViewportPlaceholder()

            case .split:
                HSplitView {
                    NetworkViewport()
                    VideoViewportPlaceholder()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SNCFPalette.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SNCFPalette.metal, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct VideoViewportPlaceholder: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.22)

            VStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)

                Text("VIDÉO")
                    .font(.caption.bold())
                    .foregroundColor(SNCFPalette.label)

                Text("Flux caméra locomotive")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Prévu pour une évolution future")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(
            minWidth: 260,
            maxWidth: .infinity,
            minHeight: 220,
            maxHeight: .infinity
        )
    }
}
