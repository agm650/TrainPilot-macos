import SwiftUI

struct FunctionPanel: View {
    @ObservedObject var session: DrivingSession
    let functionCount: Int
    let columnCount: Int
    let disabled: Bool
    let onToggle: (Int) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 54),
                spacing: 8
            ),
            count: max(1, columnCount)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FONCTIONS")
                .font(.caption.bold())
                .foregroundColor(SNCFPalette.label)

            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(
                        0..<max(functionCount, 1),
                        id: \.self
                    ) { function in
                        let active =
                            session.functionStates[function] ?? false

                        Button {
                            onToggle(function)
                        } label: {
                            VStack(spacing: 3) {
                                Text("F\(function)")
                                    .font(.callout.bold())

                                Circle()
                                    .fill(
                                        active
                                        ? SNCFPalette.green
                                        : Color.secondary.opacity(0.35)
                                    )
                                    .frame(width: 7, height: 7)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 44
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(SNCFPalette.gauge)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    active
                                    ? SNCFPalette.metal
                                    : SNCFPalette.panel
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    SNCFPalette.metal,
                                    lineWidth: 1
                                )
                        )
                        .disabled(disabled)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SNCFPalette.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            SNCFPalette.metal,
                            lineWidth: 2
                        )
                )
        )
    }
}
