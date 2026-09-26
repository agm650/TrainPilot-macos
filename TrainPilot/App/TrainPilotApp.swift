import SwiftUI

@main
struct TrainPilotApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("TrainPilot") {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Enregistrer le brouillon") {
                    Task { await appModel.saveLayoutDraft() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appModel.layoutEditorDocument == nil)
            }

            CommandMenu("Layout") {
                Button("Importer un layout…") {
                    WindowCoordinator.shared.importLayout(appModel: appModel)
                }
                .disabled(
                    !LayoutTransferPolicy.canImport(
                        currentUser: appModel.currentUser,
                        connectionState: appModel.connectionState
                    )
                )

                Button("Exporter le layout actuel…") {
                    WindowCoordinator.shared.exportLayout(appModel: appModel)
                }
                .disabled(
                    !LayoutTransferPolicy.canExport(
                        currentUser: appModel.currentUser,
                        connectionState: appModel.connectionState
                    )
                )

                Divider()

                Button("Ouvrir dans Layout Studio…") {
                    WindowCoordinator.shared.showLayoutStudio(appModel: appModel)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!LayoutStudioAccessPolicy.canOpen(currentUser: appModel.currentUser))
            }

            CommandMenu("TrainPilot") {
                Button("Bibliothèque…") {
                    WindowCoordinator.shared.showLibrary(appModel: appModel)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Arrêt d'urgence") {
                    Task { await appModel.emergencyStop() }
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(appModel.connectionState != .ready)

                Divider()

                Button("Déconnexion") {
                    Task { await appModel.logout() }
                }
                .disabled(appModel.connectionState == .disconnected)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appModel)
                .frame(width: 540)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Group {
            if appModel.connectionState == .ready ||
                appModel.connectionState == .reconnecting ||
                appModel.connectionState == .synchronizing {
                SNCFClassicCabView()
            } else {
                LoginView()
            }
        }
        .task {
            await appModel.restoreSessionIfPossible()
        }
    }
}
