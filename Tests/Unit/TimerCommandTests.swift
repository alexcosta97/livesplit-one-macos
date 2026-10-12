import Testing

@testable import LiveSplitOne

@Suite struct TimerCommandTests {
    @Test func theServerProtocolsCommands() {
        #expect(TimerCommand.splitOrStart.json == #"{"command":"splitOrStart"}"#)
        #expect(TimerCommand.reset.json == #"{"command":"reset"}"#)
        #expect(TimerCommand.undoSplit.json == #"{"command":"undoSplit"}"#)
        #expect(TimerCommand.skipSplit.json == #"{"command":"skipSplit"}"#)
        #expect(TimerCommand.pause.json == #"{"command":"pause"}"#)
        #expect(TimerCommand.resume.json == #"{"command":"resume"}"#)
        #expect(TimerCommand.undoAllPauses.json == #"{"command":"undoAllPauses"}"#)
        #expect(
            TimerCommand.setTimingMethod(.gameTime).json
                == #"{"command":"setCurrentTimingMethod","timingMethod":"GameTime"}"#)
        #expect(
            TimerCommand.setTimingMethod(.realTime).json
                == #"{"command":"setCurrentTimingMethod","timingMethod":"RealTime"}"#)
    }

    @Test func theTimingMethodsMenuTitles() {
        #expect(TimingMethod.realTime.title == "Real Time")
        #expect(TimingMethod.gameTime.title == "Game Time")
    }

    @Test func aComparisonNameIsEscaped() {
        #expect(
            TimerCommand.setComparison(#"Sub "Any%" / v2"#).json
                == #"{"command":"setCurrentComparison","comparison":"Sub \"Any%\" / v2"}"#)
    }

    @Test func namesForTheLog() {
        #expect(TimerCommand.splitOrStart.logName == "Start/Split")
        #expect(TimerCommand.resume.logName == "Resume")
        #expect(
            TimerCommand.setComparison("Best Segments").logName == "Compare Against Best Segments")
        #expect(TimerCommand.setTimingMethod(.gameTime).logName == "Game Time")
        #expect(TimerCommand.setTimingMethod(.realTime).logName == "Real Time")
    }
}
