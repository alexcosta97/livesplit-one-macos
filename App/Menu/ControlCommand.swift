/// The Control menu's commands (spec §7), the ones that have keyboard shortcuts (§7.2). The raw
/// value is the command's key in `app.toml`'s `[shortcuts]` table (§11).
enum ControlCommand: String, CaseIterable, Sendable {
    case startSplit = "start_split"
    case reset
    case undoSplit = "undo_split"
    case skipSplit = "skip_split"
    case pause
    case undoAllPauses = "undo_all_pauses"

    /// Its name in the Settings window. The menus show `TimerMenuState.title(for:)`, which
    /// follows the timer.
    var name: String {
        switch self {
        case .startSplit: "Start/Split"
        case .reset: "Reset"
        case .undoSplit: "Undo Split"
        case .skipSplit: "Skip Split"
        case .pause: "Pause/Resume"
        case .undoAllPauses: "Undo All Pauses"
        }
    }
}
