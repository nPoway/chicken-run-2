import Foundation

enum AppConfiguration {
    static let appleAppID = "6793132698"
    static let storeID = "id6793132698"
    static let expectedBundleID = "app.skyboundsteps"

    static let siteURL = URL(string: "https://roadtoheavenluetti.com")!
    static let privacyPolicyURL = URL(string: "https://roadtoheavenluetti.com/privacy-policy.html")!
    static let supportURL = URL(string: "https://roadtoheavenluetti.com/support.html")!
    static let configURL = URL(string: "https://roadtoheavenluetti.com/config.php")!

    /// The target AppsFlyer key was not supplied. Keeping it in target configuration
    /// allows the real key to be added without ever inheriting a source-project value.
    static var appsFlyerDevKey: String? {
        infoString(named: "AppsFlyerDevKey")
    }

    /// These values are read only from the target's GoogleService-Info.plist once it
    /// is supplied and bundled with the main app.
    static var firebaseProjectID: String? {
        firebaseConfiguration["PROJECT_ID"] as? String
    }

    static var firebaseProjectNumber: String? {
        firebaseConfiguration["GCM_SENDER_ID"] as? String
    }

    static var hasFirebaseConfiguration: Bool {
        !firebaseConfiguration.isEmpty
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? expectedBundleID
    }

    private static var firebaseConfiguration: [String: Any] {
        guard
            let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
            let configuration = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            return [:]
        }

        return configuration
    }

    private static func infoString(named key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
