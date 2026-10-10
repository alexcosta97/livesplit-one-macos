import Testing

@testable import LiveSplitOne

@Suite struct GameTimeLogFilterTests {
    let gameTime = #"{"command":"setGameTime","time":"1:23.5"}"#
    let laterGameTime = #"{"command":"setGameTime","time":"1:23.6"}"#
    let split = #"{"command":"split"}"#

    @Test func theFirstGameTimeOfARunIsLogged() {
        var filter = GameTimeLogFilter()
        let logged = filter.shouldLog(gameTime)
        #expect(logged)
    }

    @Test func gameTimesRightAfterItAreNot() {
        var filter = GameTimeLogFilter()
        let logged = [gameTime, laterGameTime, gameTime, laterGameTime].map {
            filter.shouldLog($0)
        }
        #expect(logged == [true, false, false, false])
    }

    @Test func anyOtherCommandIsLoggedAndEndsTheRun() {
        var filter = GameTimeLogFilter()
        let logged = [gameTime, laterGameTime, split, gameTime, laterGameTime].map {
            filter.shouldLog($0)
        }
        #expect(logged == [true, false, true, true, false])
    }

    @Test func aMessageThatIsntACommandIsLoggedAndEndsTheRun() {
        var filter = GameTimeLogFilter()
        let logged = [gameTime, "not json", gameTime, #"{"time":"1"}"#, gameTime].map {
            filter.shouldLog($0)
        }
        #expect(logged == [true, true, true, true, true])
    }

    @Test func theCommandIsReadFromTheMessage() {
        #expect(GameTimeLogFilter.command(of: gameTime) == "setGameTime")
        #expect(GameTimeLogFilter.command(of: split) == "split")
        #expect(GameTimeLogFilter.command(of: "[1,2]") == nil)
        #expect(GameTimeLogFilter.command(of: #"{"command":5}"#) == nil)
    }
}
