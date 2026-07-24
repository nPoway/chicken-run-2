import UIKit
import UserNotifications

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static weak var shared: AppDelegate?
    private static var didConfigureFirebase = false
    private var didStartAppsFlyer = false
    private var handledNotificationResponseKeys = Set<String>()
    private var supportedOrientationMask = AppDelegate.defaultSupportedOrientationMask

    override init() {
        _ = Self.configureFirebaseIfNeeded()
        super.init()
        Self.shared = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let firebaseConfigured = Self.configureFirebaseIfNeeded()

        #if canImport(FirebaseMessaging)
        if firebaseConfigured {
            Messaging.messaging().delegate = self
        }
        #endif

        UNUserNotificationCenter.current().delegate = self
        configureAppsFlyer()
        logPush(
            "did-finish-launching",
            details: [
                "launchOptionsKeys=\(Self.launchOptionKeysDescription(launchOptions))",
                "hasRemoteNotification=\(launchOptions?[.remoteNotification] != nil)",
                "firebaseConfigured=\(firebaseConfigured)"
            ]
        )
        handleLaunchNotificationIfNeeded(launchOptions)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )

        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = RoadToHeavenSceneDelegate.self
        }

        return configuration
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        supportedOrientationMask
    }

    private static func configureFirebaseIfNeeded() -> Bool {
        #if canImport(FirebaseCore)
        guard AppConfiguration.hasFirebaseConfiguration else {
            debugLog("Firebase configuration skipped: target GoogleService-Info.plist is unavailable.")
            return false
        }

        guard !didConfigureFirebase else { return true }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        didConfigureFirebase = true
        return true
        #else
        return false
        #endif
    }

    @MainActor
    static func lockGameOrientation() {
        shared?.setSupportedOrientationMask(.portrait)
    }

    @MainActor
    static func restoreDefaultOrientations() {
        shared?.setSupportedOrientationMask(defaultSupportedOrientationMask)
    }

    private static var defaultSupportedOrientationMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    @MainActor
    private func setSupportedOrientationMask(_ mask: UIInterfaceOrientationMask) {
        supportedOrientationMask = mask

        guard let windowScene = activeWindowScene else { return }

        windowScene.windows.forEach {
            $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    @MainActor
    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        handleDidBecomeActive(source: "application-did-become-active")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        logPush("will-enter-foreground")
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logPush(
            "did-register-apns-token",
            details: ["token=\(Self.redactedDeviceToken(deviceToken))"]
        )

        #if canImport(FirebaseMessaging)
        if AppConfiguration.hasFirebaseConfiguration {
            Messaging.messaging().apnsToken = deviceToken
        }
        #endif

        #if canImport(AppsFlyerLib)
        if AppConfiguration.appsFlyerDevKey != nil {
            AppsFlyerLib.shared().registerUninstall(deviceToken)
        }
        #endif
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logPush("did-receive-remote-notification-fetch", userInfo: userInfo)
        forwardPushToAppsFlyer(userInfo)
        completionHandler(.noData)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        continueAppsFlyerUserActivity(
            userActivity,
            source: "application-delegate"
        )
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        handleAppsFlyerOpenURL(
            url,
            options: options,
            source: "application-delegate"
        )
    }

    private func continueAppsFlyerUserActivity(
        _ userActivity: NSUserActivity,
        source: String
    ) -> Bool {
        #if canImport(AppsFlyerLib)
        guard AppConfiguration.appsFlyerDevKey != nil else {
            logDeepLink(
                "continue-user-activity-skip",
                source: source,
                url: userActivity.webpageURL,
                details: ["reason=appsflyer-not-configured"]
            )
            return false
        }

        logDeepLink(
            "continue-user-activity",
            source: source,
            url: userActivity.webpageURL
        )
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        return true
        #else
        logDeepLink(
            "continue-user-activity-skip",
            source: source,
            url: userActivity.webpageURL,
            details: ["reason=sdk-not-linked"]
        )
        return false
        #endif
    }

    private func handleAppsFlyerOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any],
        source: String
    ) -> Bool {
        #if canImport(AppsFlyerLib)
        guard AppConfiguration.appsFlyerDevKey != nil else {
            logDeepLink(
                "open-url-skip",
                source: source,
                url: url,
                details: ["reason=appsflyer-not-configured"]
            )
            return false
        }

        logDeepLink("open-url", source: source, url: url)
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
        #else
        logDeepLink(
            "open-url-skip",
            source: source,
            url: url,
            details: ["reason=sdk-not-linked"]
        )
        return false
        #endif
    }

    private func configureAppsFlyer() {
        #if canImport(AppsFlyerLib)
        guard let devKey = AppConfiguration.appsFlyerDevKey else {
            logPush("appsflyer-configuration-skipped", details: ["reason=missing-target-dev-key"])
            return
        }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = AppConfiguration.appleAppID
        appsFlyer.delegate = self
        appsFlyer.deepLinkDelegate = self
        registerAppsFlyerIDProvider()

        #if DEBUG
        appsFlyer.isDebug = true
        #endif
        #else
        logPush("appsflyer-configuration-skipped", details: ["reason=sdk-not-linked"])
        #endif
    }

    @MainActor
    private func handleLaunchNotificationIfNeeded(
        _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        guard
            let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any]
        else {
            logPush("cold-start-no-remote-notification")
            return
        }

        logPush("cold-start-remote-notification", userInfo: userInfo)
        handleNotificationOpen(userInfo)
    }

    @MainActor
    private func handleNotificationOpen(_ userInfo: [AnyHashable: Any]) {
        logPush("notification-open-received", userInfo: userInfo)
        forwardPushToAppsFlyer(userInfo)

        guard let url = PushNotificationService.notificationURL(from: userInfo) else {
            logPush("notification-open-no-http-url", userInfo: userInfo)
            return
        }

        logPush("notification-open-url-selected", details: ["url=\(url.absoluteString)"])

        PushNotificationService.shared.openNotificationURL(url)
    }

    @MainActor
    private func handleNotificationResponse(
        _ response: UNNotificationResponse,
        source: String
    ) {
        let request = response.notification.request
        let responseKey = "\(request.identifier)|\(response.actionIdentifier)"

        guard handledNotificationResponseKeys.insert(responseKey).inserted else {
            logPush(
                "notification-response-duplicate-skip",
                userInfo: request.content.userInfo,
                details: [
                    "source=\(source)",
                    "actionIdentifier=\(response.actionIdentifier)",
                    "requestIdentifier=\(request.identifier)"
                ]
            )
            return
        }

        logPush(
            "did-receive-notification-response",
            userInfo: request.content.userInfo,
            details: [
                "source=\(source)",
                "actionIdentifier=\(response.actionIdentifier)",
                "requestIdentifier=\(request.identifier)",
                "category=\(request.content.categoryIdentifier)"
            ]
        )
        handleNotificationOpen(request.content.userInfo)
    }

    @MainActor
    private func handleDidBecomeActive(source: String) {
        logPush("did-become-active", details: ["source=\(source)"])
        startAppsFlyerOnce()
        PushNotificationService.shared.deliverPendingNotificationURLIfPossible(source: source)
    }

    private func forwardPushToAppsFlyer(_ userInfo: [AnyHashable: Any]) {
        #if canImport(AppsFlyerLib)
        if AppConfiguration.appsFlyerDevKey != nil {
            AppsFlyerLib.shared().handlePushNotification(userInfo)
        }
        #endif
    }

    private func registerAppsFlyerIDProvider() {
        #if canImport(AppsFlyerLib)
        Task { @MainActor in
            AttributionService.shared.setAppsFlyerIDProvider {
                AppsFlyerLib.shared().getAppsFlyerUID()
            }
        }
        #endif
    }

    @MainActor
    static func startAppsFlyerForLaunch() {
        shared?.startAppsFlyerOnce()
    }

    @MainActor
    static func handleSceneNotificationResponse(_ response: UNNotificationResponse) {
        shared?.handleNotificationResponse(response, source: "scene-connection")
    }

    @MainActor
    static func handleSceneUserActivity(_ userActivity: NSUserActivity) {
        _ = shared?.continueAppsFlyerUserActivity(
            userActivity,
            source: "scene-delegate"
        )
    }

    @MainActor
    static func handleSceneOpenURLContext(_ context: UIOpenURLContext) {
        _ = shared?.handleAppsFlyerOpenURL(
            context.url,
            options: applicationOpenOptions(from: context.options),
            source: "scene-delegate"
        )
    }

    @MainActor
    static func sceneDidBecomeActive() {
        shared?.handleDidBecomeActive(source: "scene-did-become-active")
    }

    @MainActor
    private func startAppsFlyerOnce() {
        guard !didStartAppsFlyer else { return }

        #if canImport(AppsFlyerLib)
        guard AppConfiguration.appsFlyerDevKey != nil else { return }

        didStartAppsFlyer = true
        AppsFlyerLib.shared().start()

        let appsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        Task { @MainActor in
            AttributionService.shared.recordAppsFlyerID(appsFlyerID)
        }
        #endif
    }

    private func logPush(
        _ event: String,
        userInfo: [AnyHashable: Any]? = nil,
        details: [String] = []
    ) {
        #if DEBUG
        var components = [
            "[RoadToHeavenPush]",
            "AppDelegate",
            event,
            "appState=\(UIApplication.shared.applicationState.pushDebugLabel)"
        ]
        components.append(contentsOf: details)

        if let userInfo {
            components.append("payloadKeys=\(Self.payloadKeysDescription(userInfo))")
        }

        NSLog("%@", components.joined(separator: " | "))
        #endif
    }

    private func logDeepLink(
        _ event: String,
        source: String,
        url: URL?,
        details: [String] = []
    ) {
        #if DEBUG
        var components = [
            "[RoadToHeavenAttribution]",
            "AppDelegate",
            event,
            "source=\(source)",
            "url=\(url?.absoluteString ?? "nil")"
        ]
        components.append(contentsOf: details)
        NSLog("%@", components.joined(separator: " | "))
        #endif
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        NSLog("[RoadToHeavenPush] %@", message)
        #endif
    }

    nonisolated private static func launchOptionKeysDescription(
        _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> String {
        guard let launchOptions, !launchOptions.isEmpty else { return "none" }

        return launchOptions.keys
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    nonisolated private static func payloadKeysDescription(_ userInfo: [AnyHashable: Any]) -> String {
        userInfo.keys
            .map { String(describing: $0) }
            .sorted()
            .joined(separator: ",")
    }

    nonisolated private static func redactedDeviceToken(_ data: Data) -> String {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token.count > 12 else { return "length=\(token.count)" }

        return "\(token.prefix(6))...\(token.suffix(6)) length=\(token.count)"
    }

    @MainActor
    private static func applicationOpenOptions(
        from sceneOptions: UIScene.OpenURLOptions
    ) -> [UIApplication.OpenURLOptionsKey: Any] {
        var options: [UIApplication.OpenURLOptionsKey: Any] = [
            .openInPlace: sceneOptions.openInPlace
        ]

        if let sourceApplication = sceneOptions.sourceApplication {
            options[.sourceApplication] = sourceApplication
        }
        if let annotation = sceneOptions.annotation {
            options[.annotation] = annotation
        }
        if let eventAttribution = sceneOptions.eventAttribution {
            options[.eventAttribution] = eventAttribution
        }

        return options
    }
}

#if canImport(AppsFlyerLib)
extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ installData: [AnyHashable: Any]) {
        Task { @MainActor in
            AttributionService.shared.recordConversionData(installData)
        }
    }

    func onConversionDataFail(_ error: Error) {
        Task { @MainActor in
            AttributionService.shared.recordConversionFailure()
        }
    }

    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {
        Task { @MainActor in
            AttributionService.shared.recordDeepLinkData(attributionData)
        }
    }

    func onAppOpenAttributionFailure(_ error: Error) { }
}

extension AppDelegate: DeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard result.status == .found, let deepLink = result.deepLink else { return }

        var data = deepLink.clickEvent
        if let value = deepLink.deeplinkValue {
            data["deep_link_value"] = value
        }

        Task { @MainActor in
            AttributionService.shared.recordDeepLinkData(data)
        }
    }
}
#endif

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        logPush(
            "did-receive-fcm-token",
            details: ["token=\(Self.redactedStringToken(fcmToken))"]
        )
        Task { @MainActor in
            PushNotificationService.shared.updateToken(fcmToken)
        }
    }
}
#endif

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logPush(
            "will-present-notification",
            userInfo: notification.request.content.userInfo,
            details: [
                "requestIdentifier=\(notification.request.identifier)",
                "category=\(notification.request.content.categoryIdentifier)"
            ]
        )
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.handleNotificationResponse(
                response,
                source: "user-notification-center"
            )
        }
        completionHandler()
    }
}

private extension AppDelegate {
    nonisolated static func redactedStringToken(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "nil" }
        guard token.count > 12 else { return "length=\(token.count)" }

        return "\(token.prefix(6))...\(token.suffix(6)) length=\(token.count)"
    }
}

private extension UIApplication.State {
    var pushDebugLabel: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
