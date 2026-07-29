import Foundation

enum ConfigFetchResult {
    case success(url: URL, expiresAt: Date?)
    case negative
    case networkUnavailable
    case configurationUnavailable
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
        guard
            let configURL = AppConfiguration.configURL,
            AppConfiguration.storeID != nil
        else {
            log("request-rejected", details: ["reason=local-configuration-unavailable"])
            return .configurationUnavailable
        }

        var request = URLRequest(
            url: configURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let body = requestBody(payload: payload, pushToken: pushToken)
        log(
            "request-start",
            details: [
                "host=\(configURL.host ?? "nil")",
                "bodyKeys=\(Self.keysDescription(body))",
                "conversionKeys=\(Self.keysDescription(JSONNormalizer.dictionary(from: payload.conversionData)))",
                "deepLinkKeys=\(Self.keysDescription(JSONNormalizer.dictionary(from: payload.deepLinkData)))",
                "hasAppsFlyerID=\(payload.appsFlyerID != nil)",
                "hasPushToken=\(pushToken?.isEmpty == false)",
                "timeout=\(timeoutInterval)",
                "payload=\(RuntimeDebugLogSanitizer.describe(body))"
            ]
        )

        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body,
                options: []
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                log(
                    "response-negative",
                    details: [
                        "reason=non-http-response",
                        "responseBytes=\(data.count)",
                        "body=\(RuntimeDebugLogSanitizer.describeResponse(data))"
                    ]
                )
                return .negative
            }

            log(
                "response-received",
                details: [
                    "status=\(httpResponse.statusCode)",
                    "responseBytes=\(data.count)",
                    "body=\(RuntimeDebugLogSanitizer.describeResponse(data))"
                ]
            )

            guard httpResponse.statusCode == 200 else {
                log(
                    "response-negative",
                    details: [
                        "reason=http-status",
                        "status=\(httpResponse.statusCode)"
                    ]
                )
                return .negative
            }

            let configResponse: ConfigResponse
            do {
                configResponse = try JSONDecoder().decode(ConfigResponse.self, from: data)
            } catch {
                log(
                    "response-negative",
                    details: [
                        "reason=decode-failed",
                        "errorType=\(String(describing: type(of: error)))"
                    ]
                )
                return .negative
            }

            guard configResponse.ok else {
                log("response-negative", details: ["reason=backend-ok-false"])
                return .negative
            }

            guard
                let urlString = configResponse.url,
                let url = URL(string: urlString)
            else {
                log("response-negative", details: ["reason=missing-or-invalid-url"])
                return .negative
            }

            log(
                "response-success",
                details: [
                    "urlHost=\(url.host ?? "nil")",
                    "hasExpiration=\(configResponse.expiresAt != nil)",
                    "receivedURL=\(RuntimeDebugLogSanitizer.describe(url))"
                ]
            )
            return .success(url: url, expiresAt: configResponse.expiresAt)
        } catch {
            if let urlError = error as? URLError {
                log(
                    "request-network-unavailable",
                    details: ["urlErrorCode=\(urlError.code.rawValue)"]
                )
                return .networkUnavailable
            }

            log(
                "request-negative",
                details: ["errorType=\(String(describing: type(of: error)))"]
            )
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
        body["store_id"] = AppConfiguration.storeID ?? ""
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

    private static func keysDescription(_ dictionary: [String: Any]) -> String {
        dictionary.keys.sorted().joined(separator: ",")
    }

    private func log(
        _ event: String,
        details: @autoclosure () -> [String] = []
    ) {
        #if DEBUG
        var components = [
            "[RoadToHeavenConfig]",
            "ConfigClient",
            event
        ]
        components.append(contentsOf: details())
        NSLog("%@", components.joined(separator: " | "))
        #endif
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

enum JSONNormalizer {
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

nonisolated enum RuntimeDebugLogSanitizer {
    private static let explicitlySensitiveKeys: Set<String> = [
        "advertising_id",
        "af_id",
        "api_key",
        "appsflyer_id",
        "appsflyerid",
        "apns_token",
        "authorization",
        "customer_user_id",
        "dev_key",
        "device_id",
        "email",
        "fcm_token",
        "idfa",
        "idfv",
        "password",
        "phone",
        "push_token",
        "secret",
        "user_id"
    ]

    nonisolated static func describe(_ dictionary: [String: Any]) -> String {
        render(sanitize(dictionary, key: nil))
    }

    nonisolated static func describe(_ dictionary: [AnyHashable: Any]) -> String {
        describe(JSONNormalizer.dictionary(from: dictionary))
    }

    nonisolated static func describe(_ url: URL) -> String {
        sanitizedURLString(url)
    }

    nonisolated static func describeResponse(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "<non-json response; bytes=\(data.count)>"
        }

        return render(sanitize(object, key: nil))
    }

    nonisolated private static func sanitize(_ value: Any, key: String?) -> Any {
        if let key, isSensitive(key) {
            return "<redacted>"
        }

        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = sanitize(item.value, key: item.key)
            }
        case let dictionary as [AnyHashable: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, item in
                let stringKey = String(describing: item.key)
                result[stringKey] = sanitize(item.value, key: stringKey)
            }
        case let array as [Any]:
            return array.map { sanitize($0, key: key) }
        case let url as URL:
            return sanitizedURLString(url)
        case let string as String:
            if let url = URL(string: string), url.scheme != nil {
                return sanitizedURLString(url)
            }
            return clipped(string, limit: 512)
        case is NSNull, is NSNumber:
            return value
        default:
            return clipped(String(describing: value), limit: 512)
        }
    }

    nonisolated private static func sanitizedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }

        if components.user != nil {
            components.user = "<redacted>"
        }
        if components.password != nil {
            components.password = "<redacted>"
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                URLQueryItem(
                    name: item.name,
                    value: isSensitive(item.name)
                        ? "<redacted>"
                        : item.value.map { clipped($0, limit: 256) }
                )
            }
        }
        if components.fragment != nil {
            components.fragment = "<redacted>"
        }

        return clipped(components.string ?? "<invalid-url>", limit: 1_500)
    }

    nonisolated private static func isSensitive(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        return explicitlySensitiveKeys.contains(normalized)
            || normalized.contains("token")
            || normalized.contains("password")
            || normalized.contains("secret")
            || normalized.contains("authorization")
    }

    nonisolated private static func render(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "<unavailable>"
        }

        return clipped(string, limit: 3_000)
    }

    nonisolated private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return "\(value.prefix(limit))…"
    }
}
