import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct SettingsTests {
    func encode(_ settings: Settings) throws -> String { try settings.tomlText() }

    func decode(_ text: String) throws -> Settings { try Settings.decode(Data(text.utf8)) }

    /// Every setting changed from its default, with paths that aren't plain words.
    static var everySetting: Settings {
        var settings = Settings()
        settings.lastSplitsPath = #"/Users/me/Splits/Pokémon "Red" #2.lss"#
        settings.lastLayoutPath = #"/Users/me/Layouts/Pokémon "Red" #2\🏁.ls1l"#
        settings.recentSplits = RecentFiles([
            #"/Users/me/Splits/Pokémon "Red" #2.lss"#, #"/Users/me/Back\slash.lss"#, "/🏁.lss",
        ])
        settings.recentLayouts = RecentFiles([
            #"/Users/me/Layouts/Pokémon "Red" #2\🏁.ls1l"#, "/Users/me/Layouts/main.v2 (wide).ls1l",
        ])
        settings.setFrame(
            WindowFrame(x: 120, y: 640.5, width: 300, height: 520),
            forLayout: "/Users/me/Layouts/main.v2 (wide).ls1l")
        settings.setFrame(
            WindowFrame(x: -1440, y: 0, width: 280, height: 90), forLayout: "/a=b.lsl")
        settings.setFrame(
            WindowFrame(x: 10, y: 20, width: 310, height: 130),
            forLayout: #"/Users/me/Layouts/Pokémon "Red" #2\🏁.ls1l"#)
        settings.alwaysOnTop = true
        settings.lastServerURL = "ws://192.168.1.20:16834"
        return settings
    }

    @Test func theDefaults() {
        let settings = Settings()
        #expect(settings.lastSplitsPath == nil)
        #expect(settings.lastLayoutPath == nil)
        #expect(settings.recentSplits.paths.isEmpty)
        #expect(settings.recentLayouts.paths.isEmpty)
        #expect(settings.windows.isEmpty)
        #expect(!settings.alwaysOnTop)
        #expect(settings.lastServerURL == nil)
    }

    @Test func everySettingRoundTrips() throws {
        let settings = Self.everySetting
        #expect(try decode(encode(settings)) == settings)
    }

    @Test func theDefaultsAreWrittenWithoutTheUnsetKeys() throws {
        let text = try encode(Settings())
        #expect(!text.contains("last_splits"))
        #expect(!text.contains("last_server_url"))
        #expect(try decode(text) == Settings())
    }

    @Test func theFileInTheSpecReads() throws {
        // The example in spec §11.
        let text = """
            always_on_top = true
            last_layout = "/Users/me/Layouts/Main.ls1l"
            last_server_url = "ws://192.168.1.20:16834"
            last_splits = "/Users/me/Splits/GTA San Andreas.lss"
            recent_layouts = ["/Users/me/Layouts/Main.ls1l"]
            recent_splits = ["/Users/me/Splits/GTA San Andreas.lss", "/Users/me/Splits/Any%.lss"]

            [[windows]]
            layout = "/Users/me/Layouts/Main.ls1l"
            x = 120
            y = 640
            width = 300
            height = 520
            """
        let settings = try decode(text)
        #expect(settings.alwaysOnTop)
        #expect(settings.lastSplitsPath == "/Users/me/Splits/GTA San Andreas.lss")
        #expect(settings.lastLayoutPath == "/Users/me/Layouts/Main.ls1l")
        #expect(settings.lastServerURL == "ws://192.168.1.20:16834")
        #expect(settings.recentSplits.paths.count == 2)
        #expect(
            settings.frame(forLayout: "/Users/me/Layouts/Main.ls1l")
                == WindowFrame(x: 120, y: 640, width: 300, height: 520))
    }

    @Test func anEmptyFileGivesTheDefaults() throws {
        #expect(try decode("") == Settings())
    }

    @Test func missingKeysTakeTheirDefaults() throws {
        let settings = try decode("always_on_top = true\n")
        var expected = Settings()
        expected.alwaysOnTop = true
        #expect(settings == expected)
    }

    @Test func unknownKeysAreIgnored() throws {
        let settings = try decode("always_on_top = true\nhotkeys = { split = \"Space\" }\n")
        #expect(settings.alwaysOnTop)
    }

    @Test func aKeyWithTheWrongTypeIsAnError() {
        #expect(throws: (any Error).self) { try decode("always_on_top = \"yes\"\n") }
        #expect(throws: (any Error).self) { try decode("recent_splits = \"/a.lss\"\n") }
    }

    @Test func invalidTOMLIsAnErrorWithItsPlace() {
        do {
            _ = try decode("always_on_top = \n")
            Issue.record("expected an error")
        } catch {
            #expect(Settings.reason(for: error).contains("line 1"))
        }
    }

    @Test func aFrameIsReplacedNotAdded() {
        var settings = Settings()
        settings.setFrame(WindowFrame(x: 0, y: 0, width: 100, height: 100), forLayout: "/a.ls1l")
        settings.setFrame(WindowFrame(x: 5, y: 5, width: 200, height: 200), forLayout: "/a.ls1l")
        #expect(settings.windows.count == 1)
        #expect(
            settings.frame(forLayout: "/a.ls1l") == WindowFrame(x: 5, y: 5, width: 200, height: 200)
        )
        #expect(settings.frame(forLayout: "/b.ls1l") == nil)
    }

    @Test func onlyAFrameWithAFiniteSizeIsUsable() {
        #expect(WindowFrame(x: -1440, y: 0, width: 300, height: 120).isUsable)
        #expect(!WindowFrame(x: 0, y: 0, width: 0, height: 120).isUsable)
        #expect(!WindowFrame(x: 0, y: 0, width: 300, height: -1).isUsable)
        #expect(!WindowFrame(x: .nan, y: 0, width: 300, height: 120).isUsable)
        #expect(!WindowFrame(x: 0, y: 0, width: .infinity, height: 120).isUsable)
    }
}
