//
//  ChickenRunApp.swift
//  ChickenRun
//
//  Created by Nikita on 21.07.2026.
//

import SwiftUI

@main
@MainActor
struct ChickenRunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
