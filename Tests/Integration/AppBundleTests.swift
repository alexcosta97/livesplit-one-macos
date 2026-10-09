import Foundation
import Testing

private final class Marker {}

/// The built app's Info.plist. Xcode puts the app next to this test bundle.
private func appInfo() throws -> [String: Any] {
    let url = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()
        .appendingPathComponent("LiveSplit One.app")
    return try #require(Bundle(url: url)?.infoDictionary)
}

/// Checks the built app's Info.plist against spec §3 and §8.1.
@Suite struct AppBundleTests {
    @Test func namesAndIdentifierMatchTheSpec() throws {
        let info = try appInfo()
        #expect(info["CFBundleName"] as? String == "LiveSplit One")
        #expect(info["CFBundleDisplayName"] as? String == "LiveSplit One for macOS")
        #expect(info["CFBundleIdentifier"] as? String == "dev.alexcosta.livesplit-one-macos")
    }

    @Test func theMenuBarNameFitsInFifteenCharacters() throws {
        let name = try #require(try appInfo()["CFBundleName"] as? String)
        #expect(name.count <= 15)
    }

    @Test func asksForLocalNetworkAccess() throws {
        let reason = try appInfo()["NSLocalNetworkUsageDescription"] as? String
        #expect(try #require(reason).contains("livesplit-asr-bridge"))
    }

    @Test func aLocalBuildHasTheDevelopmentVersion() throws {
        let info = try appInfo()
        #expect(info["LSOVersion"] as? String == "0.0.0-dev")
        #expect(info["CFBundleShortVersionString"] as? String == "0.0.0")
    }
}
