import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct LayoutArchiveSaver {
    func save(
        _ archive: LayoutArchive,
        title: String
    ) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = normalizedFilename(
            archive.suggestedFilename
        )
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let archiveType = UTType(filenameExtension: "dcclayout") {
            panel.allowedContentTypes = [archiveType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try archive.data.write(to: url, options: .atomic)
        return url
    }

    private func normalizedFilename(_ filename: String) -> String {
        let value = filename.isEmpty ? "TrainPilot-layout.dcclayout" : filename
        return value.lowercased().hasSuffix(".dcclayout")
            ? value
            : "\(value).dcclayout"
    }
}
