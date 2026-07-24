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
}

@MainActor
final class AttributionService {
    static let shared = AttributionService()

    private(set) var latestConversionData: [AnyHashable: Any]?
    private(set) var latestDeepLinkData: [AnyHashable: Any] = [:]
    private(set) var latestAppsFlyerID: String?
    var attributionUpdatedHandler: (() -> Void)?
    private var appsFlyerIDProvider: (() -> String?)?
    private var conversionWaiters: [UUID: CheckedContinuation<AttributionResolution, Never>] = [:]
    private var deepLinkWaiters: [UUID: CheckedContinuation<[AnyHashable: Any], Never>] = [:]

    private init() { }

    func recordAppsFlyerID(_ id: String?) {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return
        }

        latestAppsFlyerID = id
    }

    func setAppsFlyerIDProvider(_ provider: @escaping () -> String?) {
        appsFlyerIDProvider = provider
    }

    func recordConversionData(_ data: [AnyHashable: Any]) {
        latestConversionData = data
        resumeWaiters(with: .resolved(data))
        attributionUpdatedHandler?()
    }

    func recordConversionFailure() {
        resumeWaiters(with: .failed)
        attributionUpdatedHandler?()
    }

    func recordDeepLinkData(_ data: [AnyHashable: Any]) {
        for (key, value) in data {
            if latestDeepLinkData[key] == nil {
                latestDeepLinkData[key] = value
            }
        }

        resumeDeepLinkWaiters()
        attributionUpdatedHandler?()
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
            appsFlyerID: resolvedAppsFlyerID
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
            appsFlyerID: resolvedAppsFlyerID
        )
    }

    private var resolvedAppsFlyerID: String? {
        if
            let freshID = appsFlyerIDProvider?()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !freshID.isEmpty
        {
            latestAppsFlyerID = freshID
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

}
