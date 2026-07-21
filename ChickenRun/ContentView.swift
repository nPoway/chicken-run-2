//
//  ContentView.swift
//  ChickenRun
//
//  Created by Nikita on 21.07.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = GameStore()
    @AppStorage("com.any.chickenrun.has-completed-onboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ZStack {
                    AppShellView(store: store)

                    if store.isPresentingGame {
                        GameContainerView(store: store)
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: store.isPresentingGame)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
