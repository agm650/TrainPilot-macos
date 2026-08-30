import AppKit

@MainActor
final class KeyboardController {
    private weak var appModel: AppModel?
    private var monitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func install() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
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
