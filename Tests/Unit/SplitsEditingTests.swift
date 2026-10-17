import AppKit
import Foundation
import LiveSplitCore
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct SplitsEditingTests {
    private func editing(_ fixture: String? = nil) throws -> SplitsEditing {
        let run =
            try fixture.map { try SplitsFile.load(Fixtures.url($0)) } ?? TimerContent.defaultRun()
        return SplitsEditing(run: run, lang: 0)
    }

    private func segment(_ editing: SplitsEditing, row: Int) throws -> RunEditorState.Segment {
        guard case .segment(let segment) = editing.state.rows[row] else {
            throw RowError()
        }
        return segment
    }

    private struct RowError: Error {}

    @Test func aTimeIsSet() throws {
        let editing = try editing()
        #expect(editing.setTime(.split, "1:00", segment: 0))
        #expect(try segment(editing, row: 0).splitTime == "1:00.00")
    }

    @Test func aTimeThatDoesntParseChangesNothing() throws {
        let editing = try editing()
        let before = editing.state
        #expect(!editing.setTime(.split, "abc", segment: 0))
        #expect(editing.state == before)
    }

    @Test func anEmptyTimeClearsIt() throws {
        let editing = try editing()
        #expect(editing.setTime(.split, "1:00", segment: 0))
        #expect(editing.setTime(.split, "", segment: 0))
        #expect(try segment(editing, row: 0).splitTime == "")
    }

    @Test func attemptsThatAreNotANumberAreRefused() throws {
        let editing = try editing()
        #expect(!editing.setAttempts("x"))
        #expect(editing.setAttempts("12"))
        #expect(editing.state.attempts == 12)
    }

    @Test func offsetParses() throws {
        let editing = try editing()
        #expect(!editing.setOffset("nope"))
        #expect(editing.setOffset("-0:05"))
    }

    @Test func aComparisonNameMustBeNewAndNotReserved() throws {
        let editing = try editing()
        #expect(editing.addComparison("Goal"))
        #expect(!editing.addComparison("Goal"))
        #expect(!editing.addComparison("[Race] x"))
        #expect(editing.state.comparisonNames == ["Goal"])
        #expect(editing.renameComparison("Goal", to: "Target"))
        #expect(editing.state.comparisonNames == ["Target"])
        editing.removeComparison("Target")
        #expect(editing.state.comparisonNames.isEmpty)
    }

    @Test func insertingASegmentGrowsTheRun() throws {
        let editing = try editing()
        editing.insertBelow()
        #expect(editing.state.rows.count == 2)
        #expect(editing.finish().len() == 2)
    }

    @Test func settingANameMakesThatSegmentActiveKeepingTheSelection() throws {
        let editing = try editing("Grouped.lss")
        editing.setName("Z", segment: 2)
        #expect(try segment(editing, row: 3).name == "Z")
        #expect(try segment(editing, row: 3).selected == .active)
        #expect(try segment(editing, row: 0).selected == .selected)
    }

    @Test func renamingAGroupToNothingInheritsTheLastSegmentsName() throws {
        let editing = try editing("Grouped.lss")
        editing.renameGroup(0, "Boss")
        guard case .group(let renamed) = editing.state.rows[1] else { throw RowError() }
        #expect(renamed.name == "Boss")
        editing.renameGroup(0, "")
        guard case .group(let group) = editing.state.rows[1] else { throw RowError() }
        #expect(group.name == "C")
        #expect(group.explicitName == nil)
    }

    @Test func theGameIconIsAnImageOnlyWhenThereIsOne() throws {
        let grouped = try editing("Grouped.lss")
        #expect(grouped.image(grouped.state.icon) != nil)
        let plain = try editing()
        #expect(plain.image(plain.state.icon) == nil)
    }

    @Test func iconsCanBeSetAndRemoved() throws {
        let editing = try editing()
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        editing.setGameIcon(png)
        #expect(editing.image(editing.state.icon) != nil)
        editing.removeGameIcon()
        #expect(editing.image(editing.state.icon) == nil)
        editing.setSegmentIcon(png, segment: 0)
        #expect(editing.image(try segment(editing, row: 0).icon) != nil)
        editing.removeSegmentIcon(segment: 0)
        #expect(editing.image(try segment(editing, row: 0).icon) == nil)
    }

    @Test func gameAndCategoryAreSet() throws {
        let editing = try editing()
        editing.setGame("Game")
        editing.setCategory("Any%")
        #expect(editing.state.game == "Game")
        #expect(editing.state.category == "Any%")
        editing.selectTimingMethod(.gameTime)
        #expect(editing.state.timingMethod == .gameTime)
    }

    @Test func linkedLayoutsAreSetAndRemoved() throws {
        let path = try editing()
        path.setLinkedLayout(.path("/a/x.lsl"))
        #expect(try #require(path.finish().linkedLayout()).path() == "/a/x.lsl")

        let standard = try editing()
        standard.setLinkedLayout(.defaultLayout)
        #expect(try #require(standard.finish().linkedLayout()).isDefault())

        let none = try editing()
        none.setLinkedLayout(.path("/a/x.lsl"))
        none.setLinkedLayout(.none)
        #expect(none.finish().linkedLayout() == nil)
    }

    @Test func aBadTimeStillMakesItsSegmentActive() throws {
        let editing = try editing()
        editing.insertBelow()
        let before = try (0..<2).map { try segment(editing, row: $0).splitTime }
        #expect(!editing.setTime(.split, "abc", segment: 1))
        #expect(try (0..<2).map { try segment(editing, row: $0).splitTime } == before)
        #expect(try segment(editing, row: 1).selected == .active)
    }

    @Test func groupsAreRemovedOnlyWhenGroupsAreSelected() throws {
        let editing = try editing("Grouped.lss")
        #expect(!editing.removeGroups())
        #expect(editing.state.rows.count == 4)
    }

    @Test func aSelectedSegmentCanBeGrouped() throws {
        let editing = try editing()
        #expect(editing.createGroup())
        guard case .group(let group) = editing.state.rows[0] else { throw RowError() }
        #expect(group.explicitName == nil)
        #expect(group.name == "Time")
        #expect(editing.state.buttons.canRemoveSegmentGroups)
        #expect(editing.removeGroups())
        #expect(editing.state.rows.count == 1)
    }

    @Test func untouchedSplitsAreNotModifiedUntilEdited() throws {
        let first = try editing()
        #expect(!first.finish().hasBeenModified())
        let second = try editing()
        second.setGame("x")
        #expect(second.finish().hasBeenModified())
    }

    @Test func selectingAGroupSelectsItsSegments() throws {
        let editing = try editing("Grouped.lss")
        editing.apply([.group(0)])
        #expect(try segment(editing, row: 0).selected == .notSelected)
        #expect(try segment(editing, row: 2).selected != .notSelected)
        #expect(try segment(editing, row: 3).selected != .notSelected)
        guard case .group(let group) = editing.state.rows[1] else { throw RowError() }
        #expect(group.selected)
        #expect(EditorSelection.selectedRows(editing.state.rows) == [1, 2, 3])
    }

    @Test func aShiftClickSelectsFromTheSelectionToTheRow() throws {
        let editing = try editing("Grouped.lss")
        editing.apply([.only(0)])
        editing.apply(EditorSelection.click(row: 3, modifier: .shift, rows: editing.state.rows))
        #expect(EditorSelection.selectedRows(editing.state.rows) == [0, 1, 2, 3])
    }

    @Test func aCommandClickTogglesASegmentInTheEditor() throws {
        let editing = try editing("Grouped.lss")
        editing.apply([.only(0)])
        editing.apply(EditorSelection.click(row: 3, modifier: .command, rows: editing.state.rows))
        #expect(EditorSelection.selectedRows(editing.state.rows) == [0, 3])
        editing.apply(EditorSelection.click(row: 3, modifier: .command, rows: editing.state.rows))
        #expect(EditorSelection.selectedRows(editing.state.rows) == [0])
    }

    @Test func aWholeTableProposalSelectsEveryRow() throws {
        let editing = try editing("Grouped.lss")
        editing.apply(
            EditorSelection.proposed([0, 1, 2, 3], current: [0], rows: editing.state.rows))
        #expect(EditorSelection.selectedRows(editing.state.rows) == [0, 1, 2, 3])
        #expect(try segment(editing, row: 3).selected == .active)
    }
}
