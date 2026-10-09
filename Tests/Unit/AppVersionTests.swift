import Testing

@testable import LiveSplitOne

@Suite struct AppVersionTests {
    @Test func usesTheBuildVersionWhenSet() {
        #expect(AppVersion.resolve("1.2.3-rc.4") == "1.2.3-rc.4")
    }

    @Test func fallsBackWhenUnset() {
        #expect(AppVersion.resolve(nil) == AppVersion.fallback)
    }

    @Test func fallsBackWhenSetButEmpty() {
        #expect(AppVersion.resolve("") == AppVersion.fallback)
    }

    @Test func fallsBackWhenNotAString() {
        #expect(AppVersion.resolve(42) == AppVersion.fallback)
    }

    @Test func theBuiltAppHasAVersion() {
        #expect(!AppVersion.current.isEmpty)
    }
}
