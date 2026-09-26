import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()

    private var libraryWindow: NSWindow?

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

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === libraryWindow else {
            return
        }

        libraryWindow = nil
    }
}
