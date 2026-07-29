import Foundation

enum AttributionResolution {
    case resolved([AnyHashable: Any])
    case failed
    case timedOut
}

struct AttributionPayload {
    var conversionData: [AnyHashable: Any]
    var deepLinkData: [AnyHashable: Any]
    var resolution: AttributionResolution
    var appsFlyerID: String?
    var hasAuthoritativeDeepLinkData: Bool

    var hasUsableAttributionData: Bool {
        !conversionData.isEmpty || !deepLinkData.isEmpty
    }

    var canFinalizeNegativeResponse: Bool {
        if case .resolved = resolution {
            return true
        }

        return hasAuthoritativeDeepLinkData
    }
}

@MainActor
final class AttributionService {
    static let shared = AttributionService()

    private(set) var latestConversionData: [AnyHashable: Any]?
    private(set) var latestDeepLinkData: [AnyHashable: Any]
    private(set) var latestAppsFlyerID: String?
    private(set) var latestIncomingURL: URL?
    private var hasAuthoritativeDeepLinkData: Bool
    private var pendingAttributionRecordedAt: Date?
    var attributionUpdatedHandler: (() -> Void)?

    private let defaults: UserDefaults
    private var appsFlyerIDProvider: (() -> String?)?
    private var conversionWaiters: [UUID: CheckedContinuation<AttributionResolution, Never>] = [:]
    private var deepLinkWaiters: [UUID: CheckedContinuation<[AnyHashable: Any], Never>] = [:]

    private static let storageKey = "app.skyboundsteps.attribution.snapshot.v1"
    private static let pendingAttributionTTL: TimeInterval = 7 * 24 * 60 * 60

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let snapshot = Self.loadSnapshot(from: defaults)
        self.latestConversionData = snapshot.conversionData
        self.latestDeepLinkData = snapshot.deepLinkData
        self.latestAppsFlyerID = snapshot.appsFlyerID
        self.latestIncomingURL = snapshot.incomingURL
        self.hasAuthoritativeDeepLinkData = snapshot.hasAuthoritativeDeepLinkData
        self.pendingAttributionRecordedAt = snapshot.pendingAttributionRecordedAt

        log(
            "snapshot-loaded",
            details: [
                "conversionKeys=\(Self.keysDescription(snapshot.conversionData ?? [:]))",
                "deepLinkKeys=\(Self.keysDescription(snapshot.deepLinkData))",
                "hasAuthoritativeDeepLink=\(snapshot.hasAuthoritativeDeepLinkData)",
                "hasAppsFlyerID=\(snapshot.appsFlyerID != nil)",
                "hasIncomingURL=\(snapshot.incomingURL != nil)",
                "hasPendingTimestamp=\(snapshot.pendingAttributionRecordedAt != nil)"
            ]
        )
    }

    func recordAppsFlyerID(_ id: String?) {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return
        }

        guard latestAppsFlyerID != id else { return }

        latestAppsFlyerID = id
        persistSnapshot()
        log("appsflyer-id-recorded", details: ["hasAppsFlyerID=true"])
    }

    func setAppsFlyerIDProvider(_ provider: @escaping () -> String?) {
        appsFlyerIDProvider = provider
    }

    func recordConversionData(_ data: [AnyHashable: Any]) {
        latestConversionData = data
        persistSnapshot()
        log(
            "conversion-recorded",
            details: [
                "incomingKeys=\(Self.keysDescription(data))",
                "storedKeys=\(Self.keysDescription(data))",
                "payload=\(RuntimeDebugLogSanitizer.describe(data))"
            ]
        )
        resumeWaiters(with: .resolved(data))
        attributionUpdatedHandler?()
    }

    func recordConversionFailure() {
        log("conversion-failed")
        resumeWaiters(with: .failed)
        attributionUpdatedHandler?()
    }

    func recordDeepLinkData(_ data: [AnyHashable: Any]) {
        data.forEach { latestDeepLinkData[$0.key] = $0.value }
        hasAuthoritativeDeepLinkData = true
        pendingAttributionRecordedAt = .now

        persistSnapshot()
        log(
            "deep-link-recorded",
            details: [
                "incomingKeys=\(Self.keysDescription(data))",
                "storedKeys=\(Self.keysDescription(latestDeepLinkData))",
                "authoritative=true",
                "payload=\(RuntimeDebugLogSanitizer.describe(data))"
            ]
        )
        resumeDeepLinkWaiters()
        attributionUpdatedHandler?()
    }

    func recordIncomingURL(_ url: URL) {
        latestIncomingURL = url

        let queryData = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [AnyHashable: Any]()) { result, item in
                result[item.name] = item.value ?? ""
            } ?? [:]

        latestDeepLinkData = queryData
        hasAuthoritativeDeepLinkData = !queryData.isEmpty
        pendingAttributionRecordedAt = .now

        log(
            "incoming-url-recorded",
            details: [
                "host=\(url.host ?? "nil")",
                "queryKeys=\(Self.keysDescription(queryData))",
                "authoritativeQuery=\(!queryData.isEmpty)",
                "url=\(RuntimeDebugLogSanitizer.describe(url))",
                "queryPayload=\(RuntimeDebugLogSanitizer.describe(queryData))"
            ]
        )

        persistSnapshot()
        resumeDeepLinkWaiters()
        if !queryData.isEmpty {
            attributionUpdatedHandler?()
        }
    }

    func markPendingAttributionConsumed() {
        guard
            latestIncomingURL != nil
            || !latestDeepLinkData.isEmpty
            || hasAuthoritativeDeepLinkData
        else {
            return
        }

        latestIncomingURL = nil
        latestDeepLinkData.removeAll()
        hasAuthoritativeDeepLinkData = false
        pendingAttributionRecordedAt = nil
        persistSnapshot()
        log("pending-attribution-consumed")
    }

    func initialPayload(timeout seconds: TimeInterval, deepLinkTimeout: TimeInterval) async -> AttributionPayload {
        async let conversionResolution = resolvedConversionData(timeout: seconds)
        async let deepLinkData = resolvedDeepLinkData(timeout: deepLinkTimeout)

        let resolution = await conversionResolution
        let conversionData: [AnyHashable: Any]
        switch resolution {
        case .resolved(let data):
            conversionData = data
        case .failed, .timedOut:
            conversionData = latestConversionData ?? [:]
        }

        return AttributionPayload(
            conversionData: conversionData,
            deepLinkData: await deepLinkData,
            resolution: resolution,
            appsFlyerID: resolvedAppsFlyerID,
            hasAuthoritativeDeepLinkData: hasAuthoritativeDeepLinkData
        )
    }

    func currentPayload() -> AttributionPayload {
        let resolution: AttributionResolution
        if let latestConversionData {
            resolution = .resolved(latestConversionData)
        } else {
            resolution = .failed
        }

        return AttributionPayload(
            conversionData: latestConversionData ?? [:],
            deepLinkData: latestDeepLinkData,
            resolution: resolution,
            appsFlyerID: resolvedAppsFlyerID,
            hasAuthoritativeDeepLinkData: hasAuthoritativeDeepLinkData
        )
    }

    private var resolvedAppsFlyerID: String? {
        if
            let freshID = appsFlyerIDProvider?()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !freshID.isEmpty
        {
            if latestAppsFlyerID != freshID {
                latestAppsFlyerID = freshID
                persistSnapshot()
            }
            return freshID
        }

        if let latestAppsFlyerID, !latestAppsFlyerID.isEmpty {
            return latestAppsFlyerID
        }

        return nil
    }

    private func resolvedConversionData(timeout seconds: TimeInterval) async -> AttributionResolution {
        if let latestConversionData {
            return .resolved(latestConversionData)
        }

        return await waitForConversionData(timeout: seconds)
    }

    private func resolvedDeepLinkData(timeout seconds: TimeInterval) async -> [AnyHashable: Any] {
        guard latestDeepLinkData.isEmpty, seconds > 0 else {
            return latestDeepLinkData
        }

        return await waitForDeepLinkData(timeout: seconds)
    }

    private func waitForConversionData(timeout seconds: TimeInterval) async -> AttributionResolution {
        let waiterID = UUID()

        return await withCheckedContinuation { continuation in
            conversionWaiters[waiterID] = continuation

            Task { [weak self] in
                let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.resumeWaiter(id: waiterID, with: .timedOut)
            }
        }
    }

    private func resumeWaiter(id: UUID, with resolution: AttributionResolution) {
        guard let continuation = conversionWaiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: resolution)
    }

    private func resumeWaiters(with resolution: AttributionResolution) {
        let waiters = conversionWaiters.values
        conversionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: resolution) }
    }

    private func waitForDeepLinkData(timeout seconds: TimeInterval) async -> [AnyHashable: Any] {
        let waiterID = UUID()

        return await withCheckedContinuation { continuation in
            deepLinkWaiters[waiterID] = continuation

            Task { [weak self] in
                let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                self?.resumeDeepLinkWaiter(id: waiterID)
            }
        }
    }

    private func resumeDeepLinkWaiter(id: UUID) {
        guard let continuation = deepLinkWaiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: latestDeepLinkData)
    }

    private func resumeDeepLinkWaiters() {
        let waiters = deepLinkWaiters.values
        deepLinkWaiters.removeAll()
        waiters.forEach { $0.resume(returning: latestDeepLinkData) }
    }

    private func persistSnapshot() {
        var snapshot: [String: Any] = [
            "conversionData": JSONNormalizer.dictionary(from: latestConversionData ?? [:]),
            "deepLinkData": JSONNormalizer.dictionary(from: latestDeepLinkData),
            "hasAuthoritativeDeepLinkData": hasAuthoritativeDeepLinkData
        ]

        if let latestAppsFlyerID {
            snapshot["appsFlyerID"] = latestAppsFlyerID
        }
        if let latestIncomingURL {
            snapshot["incomingURL"] = latestIncomingURL.absoluteString
        }
        if let pendingAttributionRecordedAt {
            snapshot["pendingAttributionRecordedAt"] = pendingAttributionRecordedAt.timeIntervalSince1970
        }

        guard
            JSONSerialization.isValidJSONObject(snapshot),
            let data = try? JSONSerialization.data(withJSONObject: snapshot)
        else {
            log("snapshot-persist-failed")
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> RestoredAttributionSnapshot {
        guard
            let data = defaults.data(forKey: storageKey),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return RestoredAttributionSnapshot()
        }

        let conversionData = dictionary(from: object["conversionData"])
        var deepLinkData = dictionary(from: object["deepLinkData"]) ?? [:]
        let appsFlyerID = (object["appsFlyerID"] as? String)?.nilIfBlank
        var incomingURL = (object["incomingURL"] as? String).flatMap(URL.init(string:))
        var hasAuthoritativeDeepLinkData =
            object["hasAuthoritativeDeepLinkData"] as? Bool
            ?? (incomingURL != nil && !deepLinkData.isEmpty)
        var pendingAttributionRecordedAt = (
            object["pendingAttributionRecordedAt"] as? NSNumber
        ).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        }

        if
            pendingAttributionRecordedAt == nil,
            incomingURL != nil || !deepLinkData.isEmpty
        {
            pendingAttributionRecordedAt = .now
        }

        if
            let recordedAt = pendingAttributionRecordedAt,
            Date().timeIntervalSince(recordedAt) > pendingAttributionTTL
        {
            deepLinkData.removeAll()
            incomingURL = nil
            hasAuthoritativeDeepLinkData = false
            pendingAttributionRecordedAt = nil
        }

        return RestoredAttributionSnapshot(
            conversionData: conversionData?.isEmpty == false ? conversionData : nil,
            deepLinkData: deepLinkData,
            appsFlyerID: appsFlyerID,
            incomingURL: incomingURL,
            hasAuthoritativeDeepLinkData: hasAuthoritativeDeepLinkData,
            pendingAttributionRecordedAt: pendingAttributionRecordedAt
        )
    }

    private static func dictionary(from value: Any?) -> [AnyHashable: Any]? {
        guard let dictionary = value as? [String: Any] else { return nil }

        return Dictionary(
            uniqueKeysWithValues: dictionary.map { (AnyHashable($0.key), $0.value) }
        )
    }

    private static func keysDescription(_ dictionary: [AnyHashable: Any]) -> String {
        dictionary.keys
            .compactMap { $0 as? String }
            .sorted()
            .joined(separator: ",")
    }

    private func log(
        _ event: String,
        details: @autoclosure () -> [String] = []
    ) {
        #if DEBUG
        var components = [
            "[RoadToHeavenAttribution]",
            "AttributionService",
            event
        ]
        components.append(contentsOf: details())
        NSLog("%@", components.joined(separator: " | "))
        #endif
    }
}

private struct RestoredAttributionSnapshot {
    var conversionData: [AnyHashable: Any]?
    var deepLinkData: [AnyHashable: Any] = [:]
    var appsFlyerID: String?
    var incomingURL: URL?
    var hasAuthoritativeDeepLinkData = false
    var pendingAttributionRecordedAt: Date?
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
