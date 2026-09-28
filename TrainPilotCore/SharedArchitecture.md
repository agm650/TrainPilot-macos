# TrainPilot shared-code boundary

`TrainPilotCore` is the platform-neutral framework shared by the macOS and iPadOS applications.

## Shared responsibilities

- API and WebSocket models
- REST and event clients
- authentication and Keychain storage
- application preferences
- connection, station, track-power and emergency-stop state
- locomotive library operations and validation
- driving sessions, leases and heartbeats
- read-only layout models, repository, rendering data and viewport mathematics
- rolling-stock archive parsing and generation

Shared source must import only frameworks available on both macOS 12 and iPadOS 16. It must not import AppKit or UIKit.

## macOS application responsibilities

- application entry point and menu commands
- window coordination
- keyboard input
- AppKit open/save panels
- layout draft storage and the complete layout editor
- macOS-specific presentation

## iPadOS application responsibilities

- application entry point and adaptive navigation
- touch-oriented library and driving interfaces
- document picker presentation
- read-only layout interaction and operational turnout commands

## Platform dependency audit

| File or area | Classification |
| --- | --- |
| Core/Models | Shared |
| Core/Networking | Shared |
| Core/Authentication/KeychainStore.swift | Shared Security API |
| Core/Preferences/AppPreferences.swift | Shared UserDefaults API |
| Driving/DrivingSession.swift | Shared |
| Driving/DrivingSessionManager.swift | Shared |
| Driving/KeyboardController.swift | macOS only (AppKit) |
| Cab/Components read-only controls/rendering | Shared SwiftUI where target-compatible |
| App/AppModel.swift | Shared application state after editor responsibilities are detached |
| App/TrainPilotApp.swift | macOS only |
| App/WindowCoordinator.swift | macOS only (AppKit) |
| Features/Library/LibraryView.swift | Platform UI; archive operations must be shared |
| Features/LayoutEditor* and Layout*Editing | macOS only |
| Features/LayoutStudio.swift | macOS only (AppKit) |
| Features/LayoutArchiveSaver.swift | macOS only (AppKit) |

Prefer target membership and module boundaries over scattered conditional compilation. Platform adapters own file selection and windowing; the server contract remains authoritative.
