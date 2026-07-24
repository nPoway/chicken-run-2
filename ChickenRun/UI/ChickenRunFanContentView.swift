//
//  ChickenRunFanContentView.swift
//  ChickenRun
//

import SwiftUI

/// The original ChickenRun root, isolated so the runtime can display it as `.fanContent`.
///
/// Keep this body in lockstep with the former standalone `ContentView` game root; the
/// launch runtime owns only the decision to show it, not the game's state or flow.
struct ChickenRunFanContentView: View {
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
    ChickenRunFanContentView()
}
