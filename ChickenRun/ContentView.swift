//
//  ContentView.swift
//  ChickenRun
//

import SwiftUI

@MainActor
struct ContentView: View {
    @State private var launchCoordinator: AppLaunchCoordinator

    init() {
        _launchCoordinator = State(initialValue: AppLaunchCoordinator())
    }

    var body: some View {
        ZStack {
            switch launchCoordinator.route {
            case .loading(let message):
                LaunchSplashView(message: message)
                    .transition(.opacity)
            case .noInternet(let message):
                NoInternetView(message: message) {
                    launchCoordinator.retry()
                }
                .transition(.opacity)
            case .fanContent:
                ChickenRunFanContentView()
                    .transition(.opacity)
                    .onAppear {
                        AppDelegate.lockGameOrientation()
                    }
                    .onDisappear {
                        AppDelegate.restoreDefaultOrientations()
                    }
            case .notificationPrompt:
                NotificationOptInView(
                    allowAction: {
                        launchCoordinator.acceptNotifications()
                    },
                    skipAction: {
                        launchCoordinator.skipNotifications()
                    }
                )
                .transition(.opacity)
            case .webView(let request):
                RoadToHeavenWebView(url: request.url, requestID: request.id)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .preferredColorScheme(.dark)
            }
        }
        .task {
            AppDelegate.startAppsFlyerForLaunch()
            await launchCoordinator.start()
        }
    }
}

#Preview {
    ContentView()
}
