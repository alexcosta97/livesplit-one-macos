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

    @MainActor
    @Test func theSpecExampleIsWhatTheAppWrites() throws {
        var settings = Settings()
        settings.alwaysOnTop = true
        settings.lastLayoutPath = "/Users/me/Layouts/Main.ls1l"
        settings.lastServerURL = "ws://192.168.1.20:16834"
        settings.lastSplitsPath = "/Users/me/Splits/GTA San Andreas.lss"
        settings.recentLayouts = RecentFiles(["/Users/me/Layouts/Main.ls1l"])
        settings.recentSplits = RecentFiles([
            "/Users/me/Splits/GTA San Andreas.lss", "/Users/me/Splits/Any%.lss",
        ])
        settings.setFrame(
            WindowFrame(x: 120, y: 640, width: 300, height: 520),
            forLayout: "/Users/me/Layouts/Main.ls1l")
        settings.setFrame(WindowFrame(x: 120, y: 300, width: 300, height: 500), forLayout: nil)
        let expected = """
            # LiveSplit One for macOS settings. The app rewrites this file when a setting changes.

            always_on_top = true
            last_layout = "/Users/me/Layouts/Main.ls1l"
            last_server_url = "ws://192.168.1.20:16834"
            last_splits = "/Users/me/Splits/GTA San Andreas.lss"
            recent_layouts = ["/Users/me/Layouts/Main.ls1l"]
            recent_splits = ["/Users/me/Splits/GTA San Andreas.lss", "/Users/me/Splits/Any%.lss"]

            [default_layout_window]
            height = 500.0
            width = 300.0
            x = 120.0
            y = 300.0

            [[windows]]
            height = 520.0
            layout = "/Users/me/Layouts/Main.ls1l"
            width = 300.0
            x = 120.0
            y = 640.0

            """
        #expect(SettingsStore.header + (try settings.tomlText()) == expected)
    }

    @Test func aHandEditedFileWithWholeNumbersReads() throws {
        // Like the example in spec §11, but as someone would type it: whole numbers, and keys
        // in the order they like. The app writes them as `120.0`, sorted.
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

    @Test func windowsWithoutAUsableFrameAreDropped() throws {
        let settings = try decode(
            """
            [[windows]]
            layout = "/nan.ls1l"
            x = nan
            y = 0
            width = 300
            height = 100

            [[windows]]
            layout = "/flat.ls1l"
            x = 0
            y = 0
            width = 0
            height = 100

            [[windows]]
            layout = "/good.ls1l"
            x = 1
            y = 2
            width = 300
            height = 100
            """)
        #expect(settings.windows.map(\.layout) == ["/good.ls1l"])
    }

    @Test func aLayoutTwiceKeepsTheFirstWindow() throws {
        let settings = try decode(
            """
            [[windows]]
            layout = "/a.ls1l"
            x = 1
            y = 2
            width = 300
            height = 100

            [[windows]]
            layout = "/a.ls1l"
            x = 9
            y = 9
            width = 400
            height = 200
            """)
        #expect(settings.windows.count == 1)
        #expect(
            settings.frame(forLayout: "/a.ls1l") == WindowFrame(x: 1, y: 2, width: 300, height: 100)
        )
    }

    @Test func aWindowMissingAKeyMakesTheFileUnreadable() {
        #expect(throws: (any Error).self) {
            try decode(
                """
                [[windows]]
                layout = "/a.ls1l"
                x = 1
                y = 2
                width = 300
                """)
        }
    }

    @Test func aDefaultLayoutWindowMissingAKeyMakesTheFileUnreadable() {
        #expect(throws: (any Error).self) {
            try decode(
                """
                [default_layout_window]
                x = 1
                y = 2
                width = 300
                """)
        }
    }

    @Test func aNaNWindowDoesNotMakeSettingsDifferFromThemselves() throws {
        let text = "[[windows]]\nlayout = \"/a.ls1l\"\nx = nan\ny = 0\nwidth = 300\nheight = 100\n"
        let first = try decode(text)
        var changed = first
        changed.alwaysOnTop = first.alwaysOnTop
        #expect(first == (try decode(text)))
        #expect(changed == first)
        #expect(first.windows.isEmpty)
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

    @Test func theDefaultLayoutsFrameIsKeptApartFromLayoutFiles() throws {
        var settings = Settings()
        let frame = WindowFrame(x: 10, y: 20, width: 300, height: 500)
        settings.setFrame(frame, forLayout: nil)

        #expect(settings.frame(forLayout: nil) == frame)
        #expect(settings.windows.isEmpty)
        let text = try settings.tomlText()
        #expect(text.contains("[default_layout_window]"))
        #expect(try Settings.decode(Data(text.utf8)) == settings)
    }

    @Test func aWholeNumberDefaultLayoutFrameLoads() throws {
        let text = """
            [default_layout_window]
            x = 100
            y = 200
            width = 300
            height = 500
            """
        let settings = try Settings.decode(Data(text.utf8))
        #expect(settings.defaultLayoutFrame == WindowFrame(x: 100, y: 200, width: 300, height: 500))
    }

    @Test func anUnusableDefaultLayoutFrameIsDropped() throws {
        let text = """
            [default_layout_window]
            x = 0
            y = 0
            width = 0
            height = 500
            """
        #expect(try Settings.decode(Data(text.utf8)).defaultLayoutFrame == nil)
    }

    @Test func aLayoutPathStillKeysItsOwnFrame() {
        var settings = Settings()
        let frame = WindowFrame(x: 1, y: 2, width: 3, height: 4)
        settings.setFrame(frame, forLayout: "/Users/me/Layouts/main.ls1l")
        #expect(settings.frame(forLayout: "/Users/me/Layouts/main.ls1l") == frame)
        #expect(settings.frame(forLayout: nil) == nil)
    }
}
