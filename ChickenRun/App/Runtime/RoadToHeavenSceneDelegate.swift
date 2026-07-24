import UIKit
import UserNotifications

@MainActor
final class RoadToHeavenSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let response = connectionOptions.notificationResponse {
            AppDelegate.handleSceneNotificationResponse(response)
        }

        connectionOptions.userActivities.forEach {
            AppDelegate.handleSceneUserActivity($0)
        }
        connectionOptions.urlContexts.forEach {
            AppDelegate.handleSceneOpenURLContext($0)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        AppDelegate.handleSceneUserActivity(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach {
            AppDelegate.handleSceneOpenURLContext($0)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AppDelegate.sceneDidBecomeActive()
    }
}
