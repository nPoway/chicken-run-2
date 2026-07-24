import Foundation

enum ConfigFetchResult {
    case success(url: URL, expiresAt: Date?)
    case negative
    case networkUnavailable
}

struct ConfigClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLink(
        payload: AttributionPayload,
        pushToken: String?,
        timeoutInterval: TimeInterval = 4
    ) async -> ConfigFetchResult {
        var request = URLRequest(url: AppConfiguration.configURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: requestBody(payload: payload, pushToken: pushToken),
                options: []
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .negative
            }

            guard httpResponse.statusCode == 200 else {
                return .negative
            }

            let configResponse = try JSONDecoder().decode(ConfigResponse.self, from: data)
            guard
                configResponse.ok,
                let urlString = configResponse.url,
                let url = URL(string: urlString)
            else {
                return .negative
            }

            return .success(url: url, expiresAt: configResponse.expiresAt)
        } catch {
            if error is URLError {
                return .networkUnavailable
            }

            return .negative
        }
    }

    private func requestBody(
        payload: AttributionPayload,
        pushToken: String?
    ) -> [String: Any] {
        var body = JSONNormalizer.dictionary(from: payload.conversionData)

        let deepLinkData = JSONNormalizer.dictionary(from: payload.deepLinkData)
        for (key, value) in deepLinkData where body[key] == nil {
            body[key] = value
        }

        body["af_id"] = payload.appsFlyerID ?? ""
        body["bundle_id"] = AppConfiguration.bundleID
        body["os"] = "iOS"
        body["store_id"] = AppConfiguration.storeID
        body["locale"] = Locale.current.identifier.replacingOccurrences(of: "-", with: "_")

        if
            let pushToken,
            !pushToken.isEmpty,
            let firebaseProjectNumber = AppConfiguration.firebaseProjectNumber
        {
            body["push_token"] = pushToken
            body["firebase_project_id"] = firebaseProjectNumber
        }

        return body
    }
}

private struct ConfigResponse: Decodable {
    let ok: Bool
    let url: String?
    let expires: TimeInterval?

    var expiresAt: Date? {
        guard let expires else { return nil }
        return Date(timeIntervalSince1970: expires)
    }
}

private enum JSONNormalizer {
    nonisolated static func dictionary(from source: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in source {
            guard let key = key as? String else { continue }
            result[key] = normalized(value)
        }

        return result
    }

    nonisolated private static func normalized(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let bool as Bool:
            return bool
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let array as [Any]:
            return array.map(normalized)
        case let dictionary as [AnyHashable: Any]:
            return self.dictionary(from: dictionary)
        case let url as URL:
            return url.absoluteString
        default:
            return String(describing: value)
        }
    }
}
