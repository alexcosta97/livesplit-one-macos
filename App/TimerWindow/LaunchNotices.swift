/// The overlay notices shown at launch (spec §6, §10).
enum LaunchNotices {
    /// The notice for what reading `app.toml` found, if it needs one.
    static func settings(_ outcome: SettingsStore.LoadOutcome) -> String? {
        switch outcome {
        case .missing, .loaded:
            nil
        case .recovered:
            "Couldn't read the settings, so the defaults are used. The old file is app.toml.bad."
        case .unrecoverable:
            "Couldn't read the settings, so the defaults are used and changes aren't saved."
        }
    }
}
