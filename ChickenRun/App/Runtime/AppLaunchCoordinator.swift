import Foundation
import Observation

enum AppLaunchRoute: Equatable {
    case loading(message: String)
    case noInternet(message: String)
    case fanContent
    case notificationPrompt(URL)
    case webView(WebViewLaunchRequest)
}

struct WebViewLaunchRequest: Equatable {
    let id: UUID
    let url: URL

    init(url: URL, id: UUID = UUID()) {
        self.id = id
        self.url = url
    }
}

@MainActor
@Observable
final class AppLaunchCoordinator {
    var route: AppLaunchRoute = .loading(message: "Preparing launch")

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let attributionService: AttributionService
    @ObservationIgnored private let pushService: PushNotificationService
    @ObservationIgnored private let configClient: ConfigClient
    @ObservationIgnored private var storedState: StoredLaunchState
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var isWaitingForLateAttribution = false
    @ObservationIgnored private var isRetryingAfterLateAttribution = false
    @ObservationIgnored private var notificationRouteIsActive = false

    private static let storageKey = "app.skyboundsteps.launch.state.v1"
    private static let conversionWaitTimeout: TimeInterval = 6.5
    private static let deepLinkWaitTimeout: TimeInterval = 1
    private static let firstLaunchConfigTimeout: TimeInterval = 3
    private static let lateAttributionConfigTimeout: TimeInterval = 3
    private static let notificationPromptDelay: TimeInterval = 3 * 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.attributionService = AttributionService.shared
        self.pushService = PushNotificationService.shared
        self.configClient = ConfigClient()
        self.storedState = Self.loadState(from: defaults)
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        logPush(
            "start",
            details: [
                "storedMode=\(storedState.mode?.rawValue ?? "nil")",
                "initialRoute=\(route.pushDebugLabel)"
            ]
        )

        pushService.notificationURLHandler = { [weak self] url in
            self?.logPush(
                "notification-url-handler-received",
                details: ["url=\(url.absoluteString)"]
            )
            _ = self?.openNotificationURL(url)
        }
        pushService.tokenUpdatedHandler = { [weak self] _ in
            self?.logPush("fcm-token-updated-handler")
            Task { @MainActor in
                await self?.refreshConfigAfterPushTokenChange()
            }
        }
        attributionService.attributionUpdatedHandler = { [weak self] in
            self?.logPush("attribution-updated-handler")
            Task { @MainActor in
                await self?.retryConfigAfterLateAttributionIfNeeded()
            }
        }

        if pushService.deliverPendingNotificationURLIfPossible(source: "coordinator-start") {
            logPush(
                "pending-notification-url-open-result",
                details: ["didOpen=true"]
            )
            return
        }

        if pushService.hasPendingNotificationURL {
            route = .loading(message: "Opening notification")
            logPush(
                "pending-notification-url-waiting",
                details: [
                    "url=\(pushService.pendingNotificationURLDescription)",
                    "reason=waiting-for-handler"
                ]
            )
            return
        }

        await resolveLaunch()
    }

    func retry() {
        guard !shouldIgnoreLaunchMutation(source: "manual-retry") else { return }

        Task {
            await resolveLaunch()
        }
    }

    func acceptNotifications() {
        guard case .notificationPrompt(let url) = route else { return }
        guard !shouldIgnoreLaunchMutation(source: "notification-permission-accept") else { return }

        Task {
            await pushService.requestAuthorizationAndRegister()
            let refreshedURL = await refreshConfigAfterPushTokenChange()
            guard !shouldIgnoreLaunchMutation(source: "notification-permission-accept-result") else { return }
            route = .webView(WebViewLaunchRequest(url: refreshedURL ?? url))
        }
    }

    func skipNotifications() {
        guard case .notificationPrompt(let url) = route else { return }
        guard !shouldIgnoreLaunchMutation(source: "notification-permission-skip") else { return }

        storedState.lastNotificationPromptSkipAt = .now
        persistState()
        route = .webView(WebViewLaunchRequest(url: url))
    }

    private func resolveLaunch() async {
        guard !shouldIgnoreLaunchMutation(source: "resolve-launch") else { return }

        switch storedState.mode {
        case .fanContent:
            route = .fanContent
        case .webView:
            await resolveStoredWebViewLaunch()
        case nil:
            await resolveFirstLaunch()
        }
    }

    private func resolveFirstLaunch() async {
        guard !shouldIgnoreLaunchMutation(source: "resolve-first-launch") else { return }

        route = .loading(message: "Checking first launch")

        let payload = await attributionService.initialPayload(
            timeout: Self.conversionWaitTimeout,
            deepLinkTimeout: Self.deepLinkWaitTimeout
        )
        logPush(
            "first-launch-config-fetch",
            details: [
                "payloadResolution=\(payload.resolution.debugLabel)",
                "timeout=\(Self.firstLaunchConfigTimeout)"
            ]
        )
        let result = await configClient.fetchLink(
            payload: payload,
            pushToken: pushService.fcmToken,
            timeoutInterval: Self.firstLaunchConfigTimeout
        )

        guard !shouldIgnoreLaunchMutation(source: "resolve-first-launch-result") else { return }

        switch result {
        case .success(let url, let expiresAt):
            isWaitingForLateAttribution = false
            storedState.mode = .webView
            storedState.lastWebURL = url
            storedState.expiresAt = expiresAt
            persistState()
            await presentWebView(url)
        case .networkUnavailable:
            route = .noInternet(message: "Internet connection is required.")
        case .negative:
            if payload.resolution.isTimedOut {
                isWaitingForLateAttribution = true
                logPush(
                    "first-launch-negative-temporary-fan",
                    details: ["reason=attribution-timed-out"]
                )
            } else {
                isWaitingForLateAttribution = false
                storedState.mode = .fanContent
                persistState()
                logPush(
                    "first-launch-negative-persist-fan",
                    details: ["payloadResolution=\(payload.resolution.debugLabel)"]
                )
            }
            route = .fanContent
        }
    }

    private func resolveStoredWebViewLaunch() async {
        guard !shouldIgnoreLaunchMutation(source: "resolve-stored-web-launch") else { return }

        guard let savedURL = storedState.lastWebURL else {
            storedState.mode = nil
            persistState()
            await resolveFirstLaunch()
            return
        }

        route = .loading(message: "Refreshing link")
        let result = await configClient.fetchLink(
            payload: attributionService.currentPayload(),
            pushToken: pushService.fcmToken
        )

        guard !shouldIgnoreLaunchMutation(source: "resolve-stored-web-launch-result") else { return }

        switch result {
        case .success(let url, let expiresAt):
            storedState.lastWebURL = url
            storedState.expiresAt = expiresAt
            persistState()
            await presentWebView(url)
        case .networkUnavailable:
            route = .noInternet(message: "Internet connection is required.")
        case .negative:
            await presentWebView(savedURL)
        }
    }

    private func retryConfigAfterLateAttributionIfNeeded() async {
        guard !shouldIgnoreLaunchMutation(source: "late-attribution-retry") else { return }

        guard isWaitingForLateAttribution else {
            logPush("late-attribution-retry-skip", details: ["reason=not-waiting"])
            return
        }

        guard !isRetryingAfterLateAttribution else {
            logPush("late-attribution-retry-skip", details: ["reason=already-retrying"])
            return
        }

        guard storedState.mode == nil else {
            isWaitingForLateAttribution = false
            logPush(
                "late-attribution-retry-skip",
                details: [
                    "reason=stored-mode-already-decided",
                    "storedMode=\(storedState.mode?.rawValue ?? "nil")"
                ]
            )
            return
        }

        let payload = attributionService.currentPayload()
        guard payload.resolution.hasResolvedConversion else {
            logPush(
                "late-attribution-retry-skip",
                details: [
                    "reason=conversion-not-resolved",
                    "payloadResolution=\(payload.resolution.debugLabel)"
                ]
            )
            return
        }

        isRetryingAfterLateAttribution = true
        defer {
            isRetryingAfterLateAttribution = false
        }

        logPush(
            "late-attribution-config-retry-start",
            details: [
                "payloadResolution=\(payload.resolution.debugLabel)",
                "timeout=\(Self.lateAttributionConfigTimeout)"
            ]
        )

        let result = await configClient.fetchLink(
            payload: payload,
            pushToken: pushService.fcmToken,
            timeoutInterval: Self.lateAttributionConfigTimeout
        )

        guard !shouldIgnoreLaunchMutation(source: "late-attribution-retry-result") else { return }

        switch result {
        case .success(let url, let expiresAt):
            isWaitingForLateAttribution = false
            storedState.mode = .webView
            storedState.lastWebURL = url
            storedState.expiresAt = expiresAt
            persistState()
            logPush("late-attribution-config-retry-success", details: ["url=\(url.absoluteString)"])
            await presentWebView(url)
        case .networkUnavailable:
            logPush("late-attribution-config-retry-network-unavailable")
        case .negative:
            isWaitingForLateAttribution = false
            storedState.mode = .fanContent
            persistState()
            logPush("late-attribution-config-retry-negative-persist-fan")
        }
    }

    private func presentWebView(_ url: URL) async {
        guard !shouldIgnoreLaunchMutation(source: "present-web-view") else { return }

        if await shouldShowNotificationPrompt() {
            guard !shouldIgnoreLaunchMutation(source: "present-notification-prompt") else { return }
            route = .notificationPrompt(url)
        } else {
            guard !shouldIgnoreLaunchMutation(source: "present-web-view-result") else { return }
            route = .webView(WebViewLaunchRequest(url: url))
        }
    }

    private func shouldShowNotificationPrompt() async -> Bool {
        guard await pushService.canRequestAuthorization() else { return false }

        if
            let skippedAt = storedState.lastNotificationPromptSkipAt,
            Date().timeIntervalSince(skippedAt) < Self.notificationPromptDelay
        {
            return false
        }

        return true
    }

    @discardableResult
    private func openNotificationURL(_ url: URL) -> Bool {
        guard url.isHTTPFamily else {
            logPush(
                "open-notification-url-rejected",
                details: [
                    "url=\(url.absoluteString)",
                    "reason=non-http-scheme"
                ]
            )
            return false
        }

        notificationRouteIsActive = true
        isWaitingForLateAttribution = false
        route = .webView(WebViewLaunchRequest(url: url))
        logPush(
            "open-notification-url-accepted",
            details: [
                "url=\(url.absoluteString)",
                "route=\(route.pushDebugLabel)"
            ]
        )
        return true
    }

    @discardableResult
    private func refreshConfigAfterPushTokenChange() async -> URL? {
        guard !shouldIgnoreLaunchMutation(source: "refresh-config-after-push-token") else {
            return nil
        }

        guard storedState.mode == .webView, pushService.fcmToken != nil else {
            logPush(
                "refresh-config-after-push-token-skip",
                details: [
                    "storedMode=\(storedState.mode?.rawValue ?? "nil")",
                    "hasFcmToken=\(pushService.fcmToken != nil)"
                ]
            )
            return nil
        }

        let result = await configClient.fetchLink(
            payload: attributionService.currentPayload(),
            pushToken: pushService.fcmToken
        )

        guard case .success(let url, let expiresAt) = result else {
            logPush("refresh-config-after-push-token-no-success")
            return nil
        }

        storedState.lastWebURL = url
        storedState.expiresAt = expiresAt
        persistState()
        logPush(
            "refresh-config-after-push-token-success",
            details: ["url=\(url.absoluteString)"]
        )
        return url
    }

    private func persistState() {
        guard let data = try? JSONEncoder().encode(storedState) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func shouldIgnoreLaunchMutation(source: String) -> Bool {
        guard notificationRouteIsActive else { return false }

        logPush(
            "launch-route-mutation-skip",
            details: [
                "source=\(source)",
                "route=\(route.pushDebugLabel)"
            ]
        )
        return true
    }

    private func logPush(_ event: String, details: [String] = []) {
        #if DEBUG
        var components = [
            "[RoadToHeavenPush]",
            "AppLaunchCoordinator",
            event
        ]
        components.append(contentsOf: details)

        NSLog("%@", components.joined(separator: " | "))
        #endif
    }

    private static func loadState(from defaults: UserDefaults) -> StoredLaunchState {
        guard
            let data = defaults.data(forKey: storageKey),
            let state = try? JSONDecoder().decode(StoredLaunchState.self, from: data)
        else {
            return StoredLaunchState()
        }

        return state
    }
}

private struct StoredLaunchState: Codable {
    var mode: StoredLaunchMode?
    var lastWebURL: URL?
    var expiresAt: Date?
    var lastNotificationPromptSkipAt: Date?
}

private enum StoredLaunchMode: String, Codable {
    case webView
    case fanContent
}

private extension AttributionResolution {
    var debugLabel: String {
        switch self {
        case .resolved:
            return "resolved"
        case .failed:
            return "failed"
        case .timedOut:
            return "timedOut"
        }
    }

    var isTimedOut: Bool {
        if case .timedOut = self {
            return true
        }

        return false
    }

    var hasResolvedConversion: Bool {
        if case .resolved = self {
            return true
        }

        return false
    }
}

private extension AppLaunchRoute {
    var pushDebugLabel: String {
        switch self {
        case .loading(let message):
            return "loading(\(message))"
        case .noInternet(let message):
            return "noInternet(\(message))"
        case .fanContent:
            return "fanContent"
        case .notificationPrompt(let url):
            return "notificationPrompt(\(url.absoluteString))"
        case .webView(let request):
            return "webView(\(request.url.absoluteString), requestID=\(request.id.uuidString))"
        }
    }
}

private extension URL {
    var isHTTPFamily: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
