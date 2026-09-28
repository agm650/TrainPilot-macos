//
//  TrainPilotPadApp.swift
//  TrainPilotPad
//
//  Created by Luc Dandoy on 28/09/2026.
//

import SwiftUI
import TrainPilotCore

@main
struct TrainPilotPadApp: App {
    private let preferences = UserDefaultsServerPreferences()

    var body: some Scene {
        WindowGroup {
            TrainPilotPadRootView(preferences: preferences)
        }
    }
}
