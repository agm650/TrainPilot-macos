import AppKit

@MainActor
final class KeyboardController {
    private weak var appModel: AppModel?
    private var monitor: Any?
    private var heldKeys: [UInt16: UUID] = [:]
    private var focusTasks: [Task<Void, Never>] = []

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func install() {
        guard monitor == nil else { return }

        for name in [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification] {
            focusTasks.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard !Task.isCancelled else { return }
                    self?.releaseHeldFunctions()
                }
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func releaseHeldFunctions() {
        appModel?.momentaryFunctions.releaseAll()
        heldKeys.removeAll()
    }

    func uninstall() {
        releaseHeldFunctions()
        focusTasks.forEach { $0.cancel() }
        focusTasks.removeAll()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Releases must work even after selection, modifiers or connection changed.
        if event.type == .keyUp {
            if let token = heldKeys.removeValue(forKey: event.keyCode) {
                appModel?.momentaryFunctions.release(token)
                return true
            }
            return false
        }
        guard let appModel,
              appModel.connectionState == .ready,
              let session = appModel.driving.activeSession else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains([.command, .option]),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            Task { await appModel.emergencyStop() }
            return true
        }

        if modifiers.contains(.command),
           let value = event.charactersIgnoringModifiers,
           let index = Int(value),
           (1...9).contains(index) {
            let sessions = appModel.driving.sortedSessions
            if index <= sessions.count {
                appModel.driving.select(locomotiveID: sessions[index - 1].locomotive.id)
            }
            return true
        }

        let increment = modifiers.contains(.shift) ? 10 : 1

        switch event.keyCode {
        case 126:
            guard session.selectorPosition != .neutral else { return true }
            appModel.setRequestedSpeed(
                locomotiveID: session.locomotive.id,
                speed: min(100, session.requestedSpeed + increment)
            )
            return true

        case 125:
            guard session.selectorPosition != .neutral else { return true }
            appModel.setRequestedSpeed(
                locomotiveID: session.locomotive.id,
                speed: max(0, session.requestedSpeed - increment)
            )
            return true

        case 123:
            Task {
                await appModel.selectDirection(
                    locomotiveID: session.locomotive.id,
                    position: .reverse
                )
            }
            return true

        case 124:
            Task {
                await appModel.selectDirection(
                    locomotiveID: session.locomotive.id,
                    position: .forward
                )
            }
            return true

        case 49:
            Task {
                await appModel.selectDirection(
                    locomotiveID: session.locomotive.id,
                    position: .neutral
                )
            }
            return true

        default:
            if let function = functionNumber(for: event.keyCode) {
                guard !event.isARepeat else { return true }
                if session.locomotive.isMomentary(function) {
                    heldKeys[event.keyCode] = appModel.pressMomentaryFunction(
                        locomotiveID: session.locomotive.id, function: function
                    )
                    return true
                }
                Task {
                    await appModel.toggleFunction(
                        locomotiveID: session.locomotive.id,
                        functionNumber: function
                    )
                }
                return true
            }
            return false
        }
    }

    private func functionNumber(for keyCode: UInt16) -> Int? {
        [
            122: 1, 120: 2, 99: 3, 118: 4,
            96: 5, 97: 6, 98: 7, 100: 8,
            101: 9, 109: 10, 103: 11, 111: 12
        ][keyCode]
    }
}
