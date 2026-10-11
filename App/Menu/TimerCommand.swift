import Foundation

/// livesplit-core's timer phases, as `Timer.currentPhase()` returns them.
enum TimerPhase: UInt8, Sendable {
    case notRunning = 0
    case running = 1
    case ended = 2
    case paused = 3
}

/// livesplit-core's timing methods, as `Timer.currentTimingMethod()` returns them.
enum TimingMethod: UInt8, CaseIterable, Sendable {
    case realTime = 0
    case gameTime = 1

    /// The menu item's title (spec §7).
    var title: String {
        switch self {
        case .realTime: "Real Time"
        case .gameTime: "Game Time"
        }
    }

    /// Its name in the server protocol.
    var protocolName: String {
        switch self {
        case .realTime: "RealTime"
        case .gameTime: "GameTime"
        }
    }
}

/// A command from the menus or the keyboard, as livesplit-core's server protocol writes it, so it
/// runs through the same command sink as the server's (spec §5.1, §7).
enum TimerCommand: Equatable, Sendable {
    case splitOrStart
    /// With no `saveAttempt`, so a reset with new best times asks `decideReset` (spec §7.1).
    case reset
    case undoSplit
    case skipSplit
    case pause
    case resume
    case undoAllPauses
    case setComparison(String)
    case setTimingMethod(TimingMethod)

    /// The command as JSON, for `EventSink.handleCommand`.
    var json: String {
        let object: [String: String] =
            switch self {
            case .splitOrStart: ["command": "splitOrStart"]
            case .reset: ["command": "reset"]
            case .undoSplit: ["command": "undoSplit"]
            case .skipSplit: ["command": "skipSplit"]
            case .pause: ["command": "pause"]
            case .resume: ["command": "resume"]
            case .undoAllPauses: ["command": "undoAllPauses"]
            case .setComparison(let name):
                ["command": "setCurrentComparison", "comparison": name]
            case .setTimingMethod(let method):
                ["command": "setCurrentTimingMethod", "timingMethod": method.protocolName]
            }
        // A dictionary of strings always serialises.
        let data = try! JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// Its name in the log (spec §12.1).
    var logName: String {
        switch self {
        case .splitOrStart: "Start/Split"
        case .reset: "Reset"
        case .undoSplit: "Undo Split"
        case .skipSplit: "Skip Split"
        case .pause: "Pause"
        case .resume: "Resume"
        case .undoAllPauses: "Undo All Pauses"
        case .setComparison(let name): "Compare Against \(name)"
        case .setTimingMethod(let method): method.title
        }
    }
}
