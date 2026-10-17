import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct RunEditorStateTests {
    private func state(of run: Run) throws -> RunEditorState {
        let editor = try #require(RunEditor(run))
        let json = editor.stateAsJson(ImageCache(), 0)
        _ = editor.close()
        return try RunEditorState.decode(json)
    }

    @Test func theDefaultRunDecodes() throws {
        let state = try state(of: TimerContent.defaultRun())
        #expect(state.timingMethod == .realTime)
        #expect(state.comparisonNames.isEmpty)
        #expect(!state.buttons.canRemove)
        #expect(state.rows.count == 1)
        guard case .segment(let segment) = state.rows[0] else {
            Issue.record("Expected a segment row")
            return
        }
        #expect(segment.name == "Time")
        #expect(segment.selected == .active)
        #expect(segment.segmentIndex == 0)
    }

    @Test func groupedSplitsDecode() throws {
        let run = try SplitsFile.load(Fixtures.url("Grouped.lss"))
        let state = try state(of: run)
        #expect(state.comparisonNames == ["Goal"])
        #expect(state.rows.count == 4)
        guard case .segment(let a) = state.rows[0], case .group(let group) = state.rows[1],
            case .segment(let b) = state.rows[2], case .segment(let c) = state.rows[3]
        else {
            Issue.record("Expected rows A, group, B, C")
            return
        }
        #expect(a.name == "A")
        #expect(!a.isIndented)
        #expect(group.name == "Last")
        #expect(group.explicitName == "Last")
        #expect(group.groupIndex == 0)
        #expect(b.name == "B")
        #expect(b.segmentIndex == 1)
        #expect(b.isIndented)
        #expect(c.name == "C")
        #expect(c.segmentIndex == 2)
        #expect(b.comparisonTimes.count == 1)
    }

    @Test func gameTimeDecodes() throws {
        let run = try SplitsFile.load(Fixtures.url("GameTime.lss"))
        let editor = try #require(RunEditor(run))
        editor.selectTimingMethod(TimingMethod.gameTime.rawValue)
        let json = editor.stateAsJson(ImageCache(), 0)
        _ = editor.close()
        #expect(try RunEditorState.decode(json).timingMethod == .gameTime)
    }
}
