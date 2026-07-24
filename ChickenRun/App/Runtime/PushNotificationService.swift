import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    private(set) var fcmToken: String?
    var tokenUpdatedHandler: ((String) -> Void)?
    var notificationURLHandler: ((URL) -> Void)?
    var hasPendingNotificationURL: Bool {
        pendingNotificationURL != nil
    }

    var pendingNotificationURLDescription: String {
        pendingNotificationURL?.absoluteString ?? "nil"
    }

    private var pendingNotificationURL: URL?
    private var pendingDeliveryRetryTask: Task<Void, Never>?

    private init() { }

    func updateToken(_ token: String?) {
        guard let token, !token.isEmpty else {
            Self.logPush("fcm-token-empty")
            return
        }

        Self.logPush("fcm-token-updated", details: ["token=\(Self.redactedStringToken(token))"])
        fcmToken = token
        tokenUpdatedHandler?(token)
    }

    func openNotificationURL(_ url: URL) {
        if let notificationURLHandler {
            Self.logPush(
                "open-notification-url-deliver-to-handler",
                details: [
                    "url=\(url.absoluteString)",
                    "appState=\(Self.applicationStateDescription())"
                ]
            )
            notificationURLHandler(url)
            return
        }

        Self.logPush(
            "open-notification-url-store-pending",
            details: [
                "url=\(url.absoluteString)",
                "reason=no-handler",
                "appState=\(Self.applicationStateDescription())"
            ]
        )
        pendingNotificationURL = url
        schedulePendingNotificationDeliveryRetry(reason: "no-handler")
    }

    @discardableResult
    func deliverPendingNotificationURLIfPossible(source: String = "direct") -> Bool {
        guard let notificationURLHandler else {
            Self.logPush(
                "deliver-pending-notification-url-skip",
                details: [
                    "source=\(source)",
                    "reason=no-handler",
                    "appState=\(Self.applicationStateDescription())",
                    "url=\(pendingNotificationURL?.absoluteString ?? "nil")"
                ]
            )
            return false
        }

        guard let url = pendingNotificationURL else {
            Self.logPush(
                "deliver-pending-notification-url-skip",
                details: [
                    "source=\(source)",
                    "reason=no-url",
                    "appState=\(Self.applicationStateDescription())"
                ]
            )
            return false
        }

        pendingNotificationURL = nil
        pendingDeliveryRetryTask?.cancel()
        pendingDeliveryRetryTask = nil
        Self.logPush(
            "deliver-pending-notification-url",
            details: [
                "source=\(source)",
                "url=\(url.absoluteString)",
                "appState=\(Self.applicationStateDescription())"
            ]
        )
        notificationURLHandler(url)
        return true
    }

    private func schedulePendingNotificationDeliveryRetry(reason: String) {
        pendingDeliveryRetryTask?.cancel()
        Self.logPush(
            "schedule-pending-notification-delivery-retry",
            details: [
                "reason=\(reason)",
                "url=\(pendingNotificationURL?.absoluteString ?? "nil")"
            ]
        )

        pendingDeliveryRetryTask = Task { @MainActor [weak self] in
            for attempt in 1...20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.pendingNotificationURL != nil else { return }

                if self.deliverPendingNotificationURLIfPossible(source: "retry-\(attempt)") {
                    return
                }
            }

            Self.logPush(
                "pending-notification-delivery-retry-exhausted",
                details: ["url=\(self?.pendingNotificationURL?.absoluteString ?? "nil")"]
            )
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func canRequestAuthorization() async -> Bool {
        await authorizationStatus() == .notDetermined
    }

    func requestAuthorizationAndRegister() async {
        let granted = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        guard granted else { return }

        UIApplication.shared.registerForRemoteNotifications()
        await refreshFCMToken()
    }

    func refreshFCMToken() async {
        guard AppConfiguration.hasFirebaseConfiguration else {
            return
        }

        #if canImport(FirebaseMessaging)
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, _ in
                Task { @MainActor in
                    self.updateToken(token)
                    continuation.resume()
                }
            }
        }
        #endif
    }

    nonisolated static func notificationURL(
        from userInfo: [AnyHashable: Any],
        path: String = "root"
    ) -> URL? {
        let urlKeys = [
            "url",
            "link",
            "deep_link",
            "deepLink",
            "target_url",
            "targetUrl",
            "af_web_dp",
            "af_dp"
        ]

        logPush(
            "parse-url-start",
            details: [
                "path=\(path)",
                "keys=\(payloadKeysDescription(userInfo))"
            ]
        )

        for key in urlKeys {
            guard let value = userInfo[key] else { continue }

            if let url = webURL(from: value) {
                logPush(
                    "parse-url-match",
                    details: [
                        "path=\(path)",
                        "key=\(key)",
                        "url=\(url.absoluteString)"
                    ]
                )
                return url
            }

            logPush(
                "parse-url-reject",
                details: [
                    "path=\(path)",
                    "key=\(key)",
                    "value=\(valueDescription(value))",
                    "reason=not-http-or-invalid"
                ]
            )
        }

        if let data = dictionaryValue(from: userInfo["data"]) {
            logPush("parse-url-descend", details: ["from=\(path)", "key=data"])
            if let url = notificationURL(from: data, path: "\(path).data") {
                return url
            }
        }

        if let aps = dictionaryValue(from: userInfo["aps"]) {
            logPush("parse-url-descend", details: ["from=\(path)", "key=aps"])
            if let url = notificationURL(from: aps, path: "\(path).aps") {
                return url
            }
        }

        logPush("parse-url-no-match", details: ["path=\(path)"])
        return nil
    }

    nonisolated private static func webURL(from value: Any?) -> URL? {
        if let url = value as? URL, url.isHTTPFamily {
            return url
        }

        guard
            let urlString = value as? String,
            !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.isHTTPFamily
        else {
            return nil
        }

        return url
    }

    nonisolated private static func dictionaryValue(from value: Any?) -> [AnyHashable: Any]? {
        if let dictionary = value as? [AnyHashable: Any] {
            return dictionary
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [AnyHashable: Any]()) { result, entry in
                result[AnyHashable(entry.key)] = entry.value
            }
        }

        return nil
    }

    nonisolated private static func payloadKeysDescription(_ userInfo: [AnyHashable: Any]) -> String {
        let keys = userInfo.keys
            .map { String(describing: $0) }
            .sorted()

        return keys.isEmpty ? "none" : keys.joined(separator: ",")
    }

    nonisolated private static func valueDescription(_ value: Any) -> String {
        let description = String(describing: value)
        guard description.count > 300 else { return description }

        return "\(description.prefix(300))..."
    }

    nonisolated private static func redactedStringToken(_ token: String) -> String {
        guard token.count > 12 else { return "length=\(token.count)" }

        return "\(token.prefix(6))...\(token.suffix(6)) length=\(token.count)"
    }

    private static func applicationStateDescription() -> String {
        switch UIApplication.shared.applicationState {
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

    nonisolated private static func logPush(_ event: String, details: [String] = []) {
        #if DEBUG
        var components = [
            "[RoadToHeavenPush]",
            "PushNotificationService",
            event
        ]
        components.append(contentsOf: details)

        NSLog("%@", components.joined(separator: " | "))
        #endif
    }
}

private extension URL {
    nonisolated var isHTTPFamily: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
