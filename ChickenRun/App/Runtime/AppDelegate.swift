import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static weak var shared: AppDelegate?
    private static var didConfigureFirebase = false
    private var lastAppsFlyerStartAt: Date?
    private var lastIncomingURLReplayAt: Date?
    private var lastReplayedIncomingURL: URL?
    private var didConfigureAppsFlyer = false
    private var supportedOrientationMask = AppDelegate.defaultSupportedOrientationMask
    private var handledNotificationResponseKeys = Set<String>()

    override init() {
        Self.configureFirebaseIfNeeded()
        super.init()
        Self.shared = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let firebaseIsConfigured = Self.configureFirebaseIfNeeded()

        if firebaseIsConfigured {
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
        configureAppsFlyer()
        logPush(
            "did-finish-launching",
            details: [
                "launchOptionsKeys=\(Self.launchOptionKeysDescription(launchOptions))",
                "hasRemoteNotification=\(launchOptions?[.remoteNotification] != nil)"
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

    @discardableResult
    private static func configureFirebaseIfNeeded() -> Bool {
        if FirebaseApp.app() != nil {
            didConfigureFirebase = true
            return true
        }

        guard !didConfigureFirebase else { return false }
        guard AppConfiguration.hasFirebaseConfiguration else {
            #if DEBUG
            NSLog("%@", "[RoadToHeavenPush] | AppDelegate | firebase-configuration-unavailable")
            #endif
            return false
        }

        FirebaseApp.configure()
        didConfigureFirebase = true
        return FirebaseApp.app() != nil
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
        if Self.didConfigureFirebase {
            Messaging.messaging().apnsToken = deviceToken
        }
        if didConfigureAppsFlyer {
            AppsFlyerLib.shared().registerUninstall(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logPush("did-receive-remote-notification-fetch", userInfo: userInfo)
        if didConfigureAppsFlyer {
            AppsFlyerLib.shared().handlePushNotification(userInfo)
        }

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

    @MainActor
    private func continueAppsFlyerUserActivity(
        _ userActivity: NSUserActivity,
        source: String
    ) -> Bool {
        if let url = userActivity.webpageURL {
            AttributionService.shared.recordIncomingURL(url)
        }

        guard didConfigureAppsFlyer else {
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
    }

    @MainActor
    private func handleAppsFlyerOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any],
        source: String
    ) -> Bool {
        AttributionService.shared.recordIncomingURL(url)

        guard didConfigureAppsFlyer else {
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
    }

    private func configureAppsFlyer() {
        guard
            let appsFlyerDevKey = AppConfiguration.appsFlyerDevKey,
            let appleAppID = AppConfiguration.appleAppID
        else {
            #if DEBUG
            NSLog("%@", "[RoadToHeavenAttribution] | AppDelegate | appsflyer-configuration-unavailable")
            #endif
            return
        }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = appsFlyerDevKey
        appsFlyer.appleAppID = appleAppID
        appsFlyer.delegate = self
        appsFlyer.deepLinkDelegate = self
        didConfigureAppsFlyer = true
        registerAppsFlyerIDProvider()

        #if DEBUG
        appsFlyer.isDebug = true
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
        if didConfigureAppsFlyer {
            AppsFlyerLib.shared().handlePushNotification(userInfo)
        }

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
        startAppsFlyer(source: source, replayIncomingURL: true)
        PushNotificationService.shared.deliverPendingNotificationURLIfPossible(source: source)
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

    private func registerAppsFlyerIDProvider() {
        Task { @MainActor in
            AttributionService.shared.setAppsFlyerIDProvider {
                AppsFlyerLib.shared().getAppsFlyerUID()
            }
        }
    }

    @MainActor
    static func startAppsFlyerForLaunch() {
        shared?.startAppsFlyer(source: "app-root-launch", replayIncomingURL: true)
    }

    @MainActor
    static func refreshAppsFlyerAttribution(source: String) {
        shared?.startAppsFlyer(source: source, replayIncomingURL: true)
    }

    @MainActor
    private func startAppsFlyer(source: String, replayIncomingURL: Bool) {
        guard didConfigureAppsFlyer else {
            logDeepLink(
                "appsflyer-start-skip",
                source: source,
                url: nil,
                details: ["reason=appsflyer-not-configured"]
            )
            return
        }

        let now = Date()
        let shouldStart = lastAppsFlyerStartAt.map {
            now.timeIntervalSince($0) >= 1
        } ?? true

        if shouldStart {
            lastAppsFlyerStartAt = now
            AppsFlyerLib.shared().start()
            AttributionService.shared.recordAppsFlyerID(
                AppsFlyerLib.shared().getAppsFlyerUID()
            )
            logDeepLink(
                "appsflyer-start",
                source: source,
                url: nil,
                details: ["replayIncomingURL=\(replayIncomingURL)"]
            )
        } else {
            logDeepLink(
                "appsflyer-start-deduplicated",
                source: source,
                url: nil
            )
        }

        if
            replayIncomingURL,
            let incomingURL = AttributionService.shared.latestIncomingURL,
            shouldReplayIncomingURL(incomingURL, now: now)
        {
            lastIncomingURLReplayAt = now
            lastReplayedIncomingURL = incomingURL
            AppsFlyerLib.shared().performOnAppAttribution(with: incomingURL)
            logDeepLink(
                "appsflyer-incoming-url-replayed",
                source: source,
                url: incomingURL
            )
        }
    }

    private func shouldReplayIncomingURL(_ url: URL, now: Date) -> Bool {
        guard
            lastReplayedIncomingURL == url,
            let lastIncomingURLReplayAt
        else {
            return true
        }

        return now.timeIntervalSince(lastIncomingURLReplayAt) >= 1
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
            "urlHost=\(url?.host ?? "nil")",
            "urlPath=\(url?.path ?? "nil")",
            "queryKeys=\(Self.queryKeysDescription(url))"
        ]
        components.append(contentsOf: details)
        NSLog("%@", components.joined(separator: " | "))
        #endif
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

    nonisolated private static func queryKeysDescription(_ url: URL?) -> String {
        guard let url else { return "none" }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .map(\.name)
            .sorted()
            .joined(separator: ",") ?? "none"
    }

    nonisolated private static func redactedDeviceToken(_ data: Data) -> String {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token.count > 12 else { return "length=\(token.count)" }

        return "\(token.prefix(6))...\(token.suffix(6)) length=\(token.count)"
    }
}

extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ installData: [AnyHashable: Any]) {
        logDeepLink(
            "conversion-success",
            source: "appsflyer-callback",
            url: nil,
            details: ["payloadKeys=\(Self.payloadKeysDescription(installData))"]
        )
        Task { @MainActor in
            AttributionService.shared.recordConversionData(installData)
        }
    }

    func onConversionDataFail(_ error: Error) {
        let nsError = error as NSError
        logDeepLink(
            "conversion-failure",
            source: "appsflyer-callback",
            url: nil,
            details: [
                "errorDomain=\(nsError.domain)",
                "errorCode=\(nsError.code)"
            ]
        )
        Task { @MainActor in
            AttributionService.shared.recordConversionFailure()
        }
    }

    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {
        logDeepLink(
            "app-open-attribution",
            source: "appsflyer-callback",
            url: nil,
            details: ["payloadKeys=\(Self.payloadKeysDescription(attributionData))"]
        )
        Task { @MainActor in
            AttributionService.shared.recordDeepLinkData(attributionData)
        }
    }

    func onAppOpenAttributionFailure(_ error: Error) {
        let nsError = error as NSError
        logDeepLink(
            "app-open-attribution-failure",
            source: "appsflyer-callback",
            url: nil,
            details: [
                "errorDomain=\(nsError.domain)",
                "errorCode=\(nsError.code)"
            ]
        )
    }
}

extension AppDelegate: DeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        logDeepLink(
            "deep-link-resolution",
            source: "appsflyer-callback",
            url: nil,
            details: ["status=\(String(describing: result.status))"]
        )

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
        Task { @MainActor [weak self] in
            self?.handleNotificationResponse(response, source: "notification-center-delegate")
            completionHandler()
        }
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
