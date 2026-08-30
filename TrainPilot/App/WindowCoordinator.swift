import AppKit
import SwiftUI

final class WindowCoordinator {
    static let shared = WindowCoordinator()

    private var libraryWindow: NSWindow?

    private init() {}

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

        window.title = "Bibliothèque TrainPilot"
        window.center()
        window.contentViewController = hosting
        window.setFrameAutosaveName("TrainPilotLibraryWindow")
        libraryWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
