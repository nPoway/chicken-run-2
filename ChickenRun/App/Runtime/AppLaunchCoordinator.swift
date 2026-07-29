import Foundation
import Network
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
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathMonitorQueue = DispatchQueue(
        label: "app.featherwind.network-recovery"
    )
    @ObservationIgnored private var storedState: StoredLaunchState
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var isWaitingForLateAttribution = false
    @ObservationIgnored private var isLaunchFlowInFlight = false
    @ObservationIgnored private var didStartNetworkMonitoring = false
    @ObservationIgnored private var lastNetworkStatus: NWPath.Status?
    @ObservationIgnored private var pendingNetworkRecoveryRetry = false
    @ObservationIgnored private var pendingAttributionRetry = false
    @ObservationIgnored private var isNotificationURLRouteActive = false

    private static let storageKey = "app.skyboundsteps.launch.state.v1"
    private static let attributionRecoveryVersion = 1
    private static let conversionWaitTimeout: TimeInterval = 6.5
    private static let deepLinkWaitTimeout: TimeInterval = 1
    private static let firstLaunchConfigTimeout: TimeInterval = 3
    private static let coldStartConfigTimeout: TimeInterval = 3
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

    deinit {
        pathMonitor.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        startNetworkMonitoringIfNeeded()
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
                await self?.handleAttributionUpdated()
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
            setRouteUnlessNotificationURLIsActive(
                .loading(message: "Opening notification"),
                source: "pending-notification-url-waiting"
            )
            logPush(
                "pending-notification-url-waiting",
                details: [
                    "url=\(pushService.pendingNotificationURLDescription)",
                    "reason=waiting-for-active-or-handler"
                ]
            )
            return
        }

        await runLaunchFlowIfIdle(
            source: "initial-launch",
            restartAttribution: false
        )
    }

    func retry() {
        guard case .noInternet = route else {
            logPush(
                "manual-retry-skip",
                details: ["reason=route-not-retryable", "route=\(route.pushDebugLabel)"]
            )
            return
        }

        Task {
            await runLaunchFlowIfIdle(
                source: "manual-retry",
                restartAttribution: true
            )
        }
    }

    func acceptNotifications() {
        guard case .notificationPrompt(let url) = route else { return }

        Task {
            await pushService.requestAuthorizationAndRegister()
            let refreshedURL = await refreshConfigAfterPushTokenChange()
            setRouteUnlessNotificationURLIsActive(
                .webView(WebViewLaunchRequest(url: refreshedURL ?? url)),
                source: "notification-primer-accept"
            )
        }
    }

    func skipNotifications() {
        guard case .notificationPrompt(let url) = route else { return }

        storedState.lastNotificationPromptSkipAt = .now
        persistState()
        setRouteUnlessNotificationURLIsActive(
            .webView(WebViewLaunchRequest(url: url)),
            source: "notification-primer-skip"
        )
    }

    private func startNetworkMonitoringIfNeeded() {
        guard !didStartNetworkMonitoring else { return }
        didStartNetworkMonitoring = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            Task { @MainActor in
                await self?.handleNetworkPathUpdate(status)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handleNetworkPathUpdate(_ status: NWPath.Status) async {
        let previousStatus = lastNetworkStatus
        lastNetworkStatus = status

        logPush(
            "network-path-updated",
            details: [
                "previous=\(previousStatus.debugLabel)",
                "current=\(status.debugLabel)"
            ]
        )

        guard status == .satisfied, previousStatus != .satisfied else { return }

        let didObserveRecoveryTransition = previousStatus != nil
        let didReceiveInitialStatusForRecoverableRoute =
            previousStatus == nil && shouldRecoverAfterNetworkRestored
        guard
            didObserveRecoveryTransition || didReceiveInitialStatusForRecoverableRoute
        else {
            return
        }

        if isLaunchFlowInFlight {
            pendingNetworkRecoveryRetry = true
            logPush(
                "network-recovery-queued",
                details: ["reason=launch-flow-in-flight"]
            )
            return
        }

        guard shouldRecoverAfterNetworkRestored else { return }

        await runLaunchFlowIfIdle(
            source: "network-restored",
            restartAttribution: true,
            pendingWhenBusy: .network
        )
    }

    private func handleAttributionUpdated() async {
        guard storedState.mode == nil else {
            isWaitingForLateAttribution = false
            attributionService.markPendingAttributionConsumed()
            logPush(
                "attribution-retry-skip",
                details: [
                    "reason=stored-mode-already-decided",
                    "storedMode=\(storedState.mode?.rawValue ?? "nil")"
                ]
            )
            return
        }

        let payload = attributionService.currentPayload()
        guard payload.hasUsableAttributionData else {
            logPush(
                "attribution-retry-skip",
                details: [
                    "reason=no-usable-attribution",
                    "payloadResolution=\(payload.resolution.debugLabel)"
                ]
            )
            return
        }

        isWaitingForLateAttribution = false

        if isLaunchFlowInFlight {
            pendingAttributionRetry = true
            logPush(
                "attribution-retry-queued",
                details: ["reason=launch-flow-in-flight"]
            )
            return
        }

        guard lastNetworkStatus != .unsatisfied else {
            pendingAttributionRetry = true
            logPush(
                "attribution-retry-queued",
                details: ["reason=network-unsatisfied"]
            )
            return
        }

        guard route.supportsAttributionRecovery else {
            logPush(
                "attribution-retry-skip",
                details: [
                    "reason=route-not-recoverable",
                    "route=\(route.pushDebugLabel)"
                ]
            )
            return
        }

        await runLaunchFlowIfIdle(
            source: "attribution-updated",
            restartAttribution: false,
            pendingWhenBusy: .attribution
        )
    }

    private func runLaunchFlowIfIdle(
        source: String,
        restartAttribution: Bool,
        pendingWhenBusy: PendingRecoveryKind? = nil
    ) async {
        guard !isLaunchFlowInFlight else {
            switch pendingWhenBusy {
            case .network:
                pendingNetworkRecoveryRetry = true
            case .attribution:
                pendingAttributionRetry = true
            case nil:
                break
            }
            logPush(
                "launch-flow-queued",
                details: [
                    "source=\(source)",
                    "restartAttribution=\(restartAttribution)",
                    "pendingKind=\(pendingWhenBusy?.debugLabel ?? "none")"
                ]
            )
            return
        }

        isLaunchFlowInFlight = true
        logPush(
            "launch-flow-start",
            details: [
                "source=\(source)",
                "restartAttribution=\(restartAttribution)"
            ]
        )

        if restartAttribution {
            AppDelegate.refreshAppsFlyerAttribution(source: source)
        }

        await resolveLaunch()

        isLaunchFlowInFlight = false
        logPush(
            "launch-flow-finished",
            details: [
                "source=\(source)",
                "route=\(route.pushDebugLabel)",
                "storedMode=\(storedState.mode?.rawValue ?? "nil")",
                "waitingForLateAttribution=\(isWaitingForLateAttribution)"
            ]
        )

        await drainPendingRecoveryWork()
    }

    private func drainPendingRecoveryWork() async {
        guard !isLaunchFlowInFlight else { return }

        let shouldRetryForNetwork = pendingNetworkRecoveryRetry
        let shouldRetryForAttribution = pendingAttributionRetry
        pendingNetworkRecoveryRetry = false
        pendingAttributionRetry = false

        if
            shouldRetryForNetwork,
            lastNetworkStatus == .satisfied,
            shouldRecoverAfterNetworkRestored
        {
            await runLaunchFlowIfIdle(
                source: "queued-network-recovery",
                restartAttribution: true
            )
            return
        }

        if shouldRetryForAttribution {
            if
                storedState.mode == nil,
                attributionService.currentPayload().hasUsableAttributionData,
                lastNetworkStatus != .unsatisfied,
                route.supportsAttributionRecovery
            {
                await runLaunchFlowIfIdle(
                    source: "queued-attribution",
                    restartAttribution: false
                )
            }
        }
    }

    private var shouldRecoverAfterNetworkRestored: Bool {
        switch route {
        case .noInternet:
            return true
        case .fanContent:
            return storedState.mode == nil
        case .loading, .notificationPrompt, .webView:
            return false
        }
    }

    private func resolveLaunch() async {
        switch storedState.mode {
        case .fanContent:
            setRouteUnlessNotificationURLIsActive(.fanContent, source: "stored-fan-mode")
        case .webView:
            await resolveStoredWebViewLaunch()
        case nil:
            await resolveFirstLaunch()
        }
    }

    private func resolveFirstLaunch() async {
        setRouteUnlessNotificationURLIsActive(
            .loading(message: "Checking first launch"),
            source: "first-launch-loading"
        )

        let payload = await attributionService.initialPayload(
            timeout: Self.conversionWaitTimeout,
            deepLinkTimeout: Self.deepLinkWaitTimeout
        )
        isWaitingForLateAttribution = !payload.canFinalizeNegativeResponse
        logPush(
            "first-launch-config-fetch",
            details: [
                "payloadResolution=\(payload.resolution.debugLabel)",
                "conversionKeyCount=\(payload.conversionData.count)",
                "deepLinkKeyCount=\(payload.deepLinkData.count)",
                "hasAuthoritativeDeepLink=\(payload.hasAuthoritativeDeepLinkData)",
                "hasAppsFlyerID=\(payload.appsFlyerID != nil)",
                "canFinalizeNegative=\(payload.canFinalizeNegativeResponse)",
                "timeout=\(Self.firstLaunchConfigTimeout)"
            ]
        )
        let result = await configClient.fetchLink(
            payload: payload,
            pushToken: pushService.fcmToken,
            timeoutInterval: Self.firstLaunchConfigTimeout
        )

        switch result {
        case .success(let url, let expiresAt):
            isWaitingForLateAttribution = false
            storedState.mode = .webView
            storedState.lastWebURL = url
            storedState.expiresAt = expiresAt
            persistState()
            attributionService.markPendingAttributionConsumed()
            await presentWebView(url)
        case .networkUnavailable:
            setRouteUnlessNotificationURLIsActive(
                .noInternet(message: "Internet connection is required."),
                source: "first-launch-network-unavailable"
            )
        case .configurationUnavailable:
            setRouteUnlessNotificationURLIsActive(
                .noInternet(message: "App configuration is unavailable."),
                source: "first-launch-configuration-unavailable"
            )
        case .negative:
            if payload.canFinalizeNegativeResponse {
                isWaitingForLateAttribution = false
                storedState.mode = .fanContent
                persistState()
                attributionService.markPendingAttributionConsumed()
                logPush(
                    "first-launch-negative-persist-fan",
                    details: ["payloadResolution=\(payload.resolution.debugLabel)"]
                )
            } else {
                isWaitingForLateAttribution = true
                logPush(
                    "first-launch-negative-temporary-fan",
                    details: [
                        "reason=attribution-not-yet-authoritative",
                        "payloadResolution=\(payload.resolution.debugLabel)"
                    ]
                )
            }
            setRouteUnlessNotificationURLIsActive(
                .fanContent,
                source: "first-launch-negative"
            )
        }
    }

    private func resolveStoredWebViewLaunch() async {
        guard let savedURL = storedState.lastWebURL else {
            storedState.mode = nil
            persistState()
            await resolveFirstLaunch()
            return
        }

        setRouteUnlessNotificationURLIsActive(
            .loading(message: "Refreshing link"),
            source: "stored-webview-refresh-loading"
        )
        let result = await configClient.fetchLink(
            payload: attributionService.currentPayload(),
            pushToken: pushService.fcmToken,
            timeoutInterval: Self.coldStartConfigTimeout
        )

        switch result {
        case .success(let url, let expiresAt):
            logPush(
                "stored-webview-refresh-success",
                details: [
                    "previousURL=\(savedURL.absoluteString)",
                    "receivedURL=\(url.absoluteString)",
                    "didChange=\(savedURL != url)"
                ]
            )
            storedState.lastWebURL = url
            storedState.expiresAt = expiresAt
            persistState()
            attributionService.markPendingAttributionConsumed()
            await presentWebView(url)
        case .networkUnavailable:
            setRouteUnlessNotificationURLIsActive(
                .noInternet(message: "Internet connection is required."),
                source: "stored-webview-network-unavailable"
            )
        case .configurationUnavailable:
            setRouteUnlessNotificationURLIsActive(
                .noInternet(message: "App configuration is unavailable."),
                source: "stored-webview-configuration-unavailable"
            )
        case .negative:
            attributionService.markPendingAttributionConsumed()
            logPush(
                "stored-webview-refresh-fallback",
                details: [
                    "reason=config-response-negative",
                    "savedURL=\(savedURL.absoluteString)"
                ]
            )
            await presentWebView(savedURL)
        }
    }

    private func presentWebView(_ url: URL) async {
        if await shouldShowNotificationPrompt() {
            setRouteUnlessNotificationURLIsActive(
                .notificationPrompt(url),
                source: "present-webview-notification-prompt"
            )
        } else {
            setRouteUnlessNotificationURLIsActive(
                .webView(WebViewLaunchRequest(url: url)),
                source: "present-webview"
            )
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

        let request = WebViewLaunchRequest(url: url)
        isNotificationURLRouteActive = true
        route = .webView(request)
        logPush(
            "open-notification-url-accepted",
            details: [
                "url=\(url.absoluteString)",
                "route=\(route.pushDebugLabel)"
            ]
        )
        return true
    }

    private func setRouteUnlessNotificationURLIsActive(
        _ newRoute: AppLaunchRoute,
        source: String
    ) {
        guard !isNotificationURLRouteActive else {
            logPush(
                "route-update-skip-notification-url-active",
                details: [
                    "source=\(source)",
                    "attemptedRoute=\(newRoute.pushDebugLabel)",
                    "currentRoute=\(route.pushDebugLabel)"
                ]
            )
            return
        }

        route = newRoute
    }

    @discardableResult
    private func refreshConfigAfterPushTokenChange() async -> URL? {
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
        storedState.attributionRecoveryVersion = Self.attributionRecoveryVersion
        guard let data = try? JSONEncoder().encode(storedState) else { return }
        defaults.set(data, forKey: Self.storageKey)
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
        var state: StoredLaunchState

        if
            let data = defaults.data(forKey: storageKey),
            let decodedState = try? JSONDecoder().decode(StoredLaunchState.self, from: data)
        {
            state = decodedState
        } else {
            state = StoredLaunchState()
        }

        let storedRecoveryVersion = state.attributionRecoveryVersion ?? 0
        guard storedRecoveryVersion < attributionRecoveryVersion else {
            return state
        }

        let didResetLegacyFanMode = state.mode == .fanContent
        if didResetLegacyFanMode {
            state.mode = nil
            state.lastWebURL = nil
            state.expiresAt = nil
        }

        state.attributionRecoveryVersion = attributionRecoveryVersion
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: storageKey)
        }

        #if DEBUG
        NSLog(
            "%@",
            [
                "[RoadToHeavenAttribution]",
                "AppLaunchCoordinator",
                "launch-state-migrated",
                "fromVersion=\(storedRecoveryVersion)",
                "toVersion=\(attributionRecoveryVersion)",
                "didResetLegacyFanMode=\(didResetLegacyFanMode)"
            ].joined(separator: " | ")
        )
        #endif

        return state
    }
}

private struct StoredLaunchState: Codable {
    var mode: StoredLaunchMode?
    var lastWebURL: URL?
    var expiresAt: Date?
    var lastNotificationPromptSkipAt: Date?
    var attributionRecoveryVersion: Int?
}

private enum StoredLaunchMode: String, Codable {
    case webView
    case fanContent
}

private enum PendingRecoveryKind {
    case network
    case attribution

    var debugLabel: String {
        switch self {
        case .network:
            return "network"
        case .attribution:
            return "attribution"
        }
    }
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
}

private extension AppLaunchRoute {
    var supportsAttributionRecovery: Bool {
        switch self {
        case .loading, .noInternet, .fanContent:
            return true
        case .notificationPrompt, .webView:
            return false
        }
    }

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

private extension Optional where Wrapped == NWPath.Status {
    var debugLabel: String {
        self?.debugLabel ?? "nil"
    }
}

private extension NWPath.Status {
    var debugLabel: String {
        switch self {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requiresConnection"
        @unknown default:
            return "unknown"
        }
    }
}

private extension URL {
    var isHTTPFamily: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
