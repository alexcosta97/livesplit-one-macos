import Foundation

/// The app's version, embedded at build time by the release pipeline (spec
/// §4.2). Local builds show the fallback.
enum AppVersion {
    /// The Info.plist key holding the full version, such as `0.4.0-rc.2`.
    /// `CFBundleShortVersionString` can only hold `0.4.0`.
    static let infoKey = "LSOVersion"
    static let fallback = "0.0.0-dev"

    static var current: String { resolve(Bundle.main.object(forInfoDictionaryKey: infoKey)) }

    /// The build's version when it is a non-empty string, otherwise the fallback.
    static func resolve(_ value: Any?) -> String {
        guard let version = value as? String, !version.isEmpty else { return fallback }
        return version
    }
}
