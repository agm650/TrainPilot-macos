import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()

    private var libraryWindow: NSWindow?
    private var layoutStudioWindow: NSWindow?
    private var layoutStudioSession: LayoutStudioSession?

    private override init() {}

    func showLibrary(appModel: AppModel) {
        if let libraryWindow {
            libraryWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = LibraryView()
            .environmentObject(appModel)

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Bibliothèque TrainPilot"
        window.center()
        window.contentViewController = hosting
        window.setFrameAutosaveName("TrainPilotLibraryWindow")
        libraryWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLayoutStudio(appModel: AppModel) {
        guard LayoutStudioAccessPolicy.canOpen(currentUser: appModel.currentUser) else {
            return
        }

        if let layoutStudioWindow {
            layoutStudioWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let session = LayoutStudioSession(
            snapshot: appModel.isAdministrator ? appModel.layoutRepository?.snapshot : nil,
            canPublish: LayoutStudioAccessPolicy.canPublish(
                currentUser: appModel.currentUser,
                connectionState: appModel.connectionState
            )
        )
        let hosting = NSHostingController(
            rootView: LayoutStudioView(session: session)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "TrainPilot Layout Studio"
        window.center()
        window.contentViewController = hosting
        window.setFrameAutosaveName("TrainPilotLayoutStudioWindow")
        layoutStudioSession = session
        layoutStudioWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func importLayout(appModel: AppModel) {
        let panel = NSOpenPanel()
        panel.title = "Importer un layout"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: "dcclayout") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try LayoutStudioArchiveService().read(from: url)
                let data = try Data(contentsOf: url)
                guard let validation = await appModel.validateLayoutImport(data) else {
                    return
                }
                guard validation.valid else {
                    showValidationAlert(validation, allowsConfirmation: false)
                    return
                }
                guard showValidationAlert(validation, allowsConfirmation: true) else {
                    return
                }
                if await appModel.importLayout(data) {
                    showInformation(
                        title: "Layout importé",
                        message: "Le layout publié a été rechargé depuis le serveur."
                    )
                }
            } catch {
                showInformation(
                    title: "Import impossible",
                    message: error.localizedDescription
                )
            }
        }
    }

    func exportLayout(appModel: AppModel) {
        Task {
            guard let archive = await appModel.exportCurrentLayout() else { return }
            do {
                _ = try LayoutArchiveSaver().save(
                    archive,
                    title: "Exporter le layout actuel"
                )
            } catch {
                showInformation(
                    title: "Export impossible",
                    message: error.localizedDescription
                )
            }
        }
    }

    @discardableResult
    private func showValidationAlert(
        _ result: LayoutValidationResult,
        allowsConfirmation: Bool
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = result.valid
            ? "Validation réussie"
            : "Le layout contient des erreurs"
        let diagnostics = result.errors + result.warnings
        alert.informativeText = diagnostics.isEmpty
            ? "Le serveur n’a signalé aucun problème. Confirmez l’import en remplacement."
            : diagnostics.map(\.message).joined(separator: "\n")
        if allowsConfirmation {
            alert.addButton(withTitle: "Importer")
            alert.addButton(withTitle: "Annuler")
            return alert.runModal() == .alertFirstButtonReturn
        }
        alert.addButton(withTitle: "Fermer")
        alert.runModal()
        return false
    }

    private func showInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === libraryWindow {
            libraryWindow = nil
        } else if window === layoutStudioWindow {
            layoutStudioWindow = nil
            layoutStudioSession = nil
        }
    }
}
