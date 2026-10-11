import Testing

@testable import LiveSplitOne

@Suite struct LaunchNoticesTests {
    @Test func readSettingsNeedNoNotice() {
        #expect(LaunchNotices.settings(.missing) == nil)
        #expect(LaunchNotices.settings(.loaded) == nil)
    }

    @Test func recoveredSettingsNameTheKeptFile() {
        #expect(
            LaunchNotices.settings(.recovered(reason: "line 3"))
                == "Couldn't read the settings, so the defaults are used. "
                + "The old file is app.toml.bad.")
    }

    @Test func unrecoverableSettingsSayChangesArentSaved() {
        #expect(
            LaunchNotices.settings(.unrecoverable(reason: "permission denied"))
                == "Couldn't read the settings, so the defaults are used and changes aren't saved."
        )
    }
}
