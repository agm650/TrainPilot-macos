import AppKit
import SwiftUI

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
