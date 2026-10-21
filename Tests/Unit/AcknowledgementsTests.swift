import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct AcknowledgementsTests {
    /// The build phase wrote the notices into the app, which hosts these tests (spec §4.4).
    @Test func theBuiltAppHasTheNotices() throws {
        let text = try #require(Acknowledgements.text())
        for expected in [
            "Fira Sans", "SIL OPEN FONT LICENSE", "swift-toml 2.0.0", "toml++ 3.4.0",
            "Bjoern Hoehrmann", "The Rust standard library", "  livesplit-core ",
            "  livesplit-core-capi ", "Apache License",
        ] {
            #expect(text.contains(expected), "no \(expected)")
        }
        // core/ is the app's own code, not third-party.
        #expect(!text.contains("lso-core"))
    }

    @Test func aBundleWithoutTheFileHasNone() {
        let tests = Bundle(for: BundleToken.self)
        #expect(Acknowledgements.text(in: tests) == nil)
    }
}

private final class BundleToken {}
