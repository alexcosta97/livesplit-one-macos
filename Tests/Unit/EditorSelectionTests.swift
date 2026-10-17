import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct EditorSelectionTests {
    typealias Row = RunEditorState.Row

    private func segment(
        _ index: Int, _ selected: RunEditorState.Selection = .notSelected, indented: Bool = false
    ) -> Row {
        .segment(
            .init(
                segmentIndex: index, icon: "", name: "", splitTime: "", segmentTime: "",
                bestSegmentTime: "", comparisonTimes: [], selected: selected,
                isIndented: indented))
    }

    private func group(_ index: Int, selected: Bool = false) -> Row {
        .group(
            .init(
                groupIndex: index, name: "Last", explicitName: nil, icon: "",
                hasExplicitIcon: false, selected: selected))
    }

    /// The rows of `Grouped.lss`: A, the group "Last", then B and C in it.
    private func rows(
        a: RunEditorState.Selection = .notSelected, b: RunEditorState.Selection = .notSelected,
        c: RunEditorState.Selection = .notSelected, group selected: Bool = false
    ) -> [Row] {
        [
            segment(0, a), group(0, selected: selected), segment(1, b, indented: true),
            segment(2, c, indented: true),
        ]
    }

    @Test func aPlainClickOnASegmentSelectsOnlyIt() {
        #expect(EditorSelection.click(row: 0, modifier: .none, rows: rows()) == [.only(0)])
        #expect(EditorSelection.click(row: 3, modifier: .none, rows: rows()) == [.only(2)])
    }

    @Test func aCommandClickTogglesASegment() {
        let selected = rows(c: .selected)
        #expect(EditorSelection.click(row: 3, modifier: .command, rows: selected) == [.unselect(2)])
        #expect(
            EditorSelection.click(row: 3, modifier: .command, rows: rows()) == [.additionally(2)])
        let active = rows(c: .active)
        #expect(EditorSelection.click(row: 3, modifier: .command, rows: active) == [.unselect(2)])
    }

    /// A new editor of the same run selects again what the old one selected, the active
    /// segment last (spec §9: a refused OK makes a new editor).
    @Test func aSelectionIsRestoredWithTheActiveSegmentLast() {
        #expect(
            EditorSelection.restoring(rows(a: .selected, b: .active, c: .selected))
                == [.only(0), .additionally(2), .additionally(1)])
        #expect(EditorSelection.restoring(rows(c: .active)) == [.only(2)])
        #expect(EditorSelection.restoring(rows()).isEmpty)
    }

    @Test func aShiftClickSelectsARange() {
        #expect(EditorSelection.click(row: 3, modifier: .shift, rows: rows()) == [.range(2)])
    }

    @Test func clicksOnAGroupUseTheGroupCalls() {
        #expect(EditorSelection.click(row: 1, modifier: .none, rows: rows()) == [.group(0)])
        #expect(
            EditorSelection.click(row: 1, modifier: .command, rows: rows()) == [.toggleGroup(0)])
        #expect(EditorSelection.click(row: 1, modifier: .shift, rows: rows()) == [.groupRange(0)])
    }

    @Test func oneProposedRowIsAPlainClick() {
        let proposed = EditorSelection.proposed(
            [3], current: [0], lastSelected: nil, rows: rows(a: .active))
        #expect(proposed == [.only(2)])
        let onGroup = EditorSelection.proposed(
            [1], current: [0], lastSelected: nil, rows: rows(a: .active))
        #expect(onGroup == [.group(0)])
    }

    @Test func oneRowAddedNextToTheSelectionExtendsIt() {
        let current = rows(a: .active)
        #expect(
            EditorSelection.proposed([0, 1], current: [0], lastSelected: nil, rows: current) == [
                .groupRange(0)
            ])
        let below = rows(b: .active)
        #expect(
            EditorSelection.proposed([2, 3], current: [2], lastSelected: nil, rows: below) == [
                .range(2)
            ])
        #expect(
            EditorSelection.proposed([1, 2], current: [2], lastSelected: nil, rows: below) == [
                .groupRange(0)
            ])
    }

    @Test func aWholeTableProposalRebuildsTheSelectionWithTheLastRowActive() {
        let proposed = EditorSelection.proposed(
            [0, 1, 2, 3], current: [0], lastSelected: nil, rows: rows(a: .active))
        #expect(proposed == [.only(0), .additionally(1), .additionally(2)])
    }

    @Test func aGroupRowInAProposalStandsForItsSegments() {
        let proposed = EditorSelection.proposed(
            [0, 1], current: [3], lastSelected: nil, rows: rows(c: .active))
        #expect(proposed == [.only(0), .additionally(1), .additionally(2)])
    }

    @Test func aShrinkRebuildsTheSelection() {
        let current = rows(a: .selected, b: .selected, c: .active)
        let proposed = EditorSelection.proposed(
            [0, 2], current: [0, 2, 3], lastSelected: nil, rows: current)
        #expect(proposed == [.only(0), .additionally(1)])
    }

    @Test func theLastSelectedRowIsAppliedLast() {
        let current = rows(a: .selected, b: .selected, c: .active)
        let shrunk = EditorSelection.proposed(
            [0, 2, 3], current: [0, 1, 2, 3], lastSelected: 0, rows: current)
        #expect(shrunk == [.only(1), .additionally(2), .additionally(0)])
        let group = EditorSelection.proposed(
            [0, 1], current: [0, 1, 2, 3], lastSelected: 1, rows: current)
        #expect(group == [.only(0), .additionally(1), .additionally(2)])
        let outside = EditorSelection.proposed(
            [0, 2, 3], current: [0, 1, 2, 3], lastSelected: 1, rows: current)
        #expect(outside == [.only(0), .additionally(1), .additionally(2)])
    }

    @Test func aProposalEqualToTheSelectionMakesNoCalls() {
        let current = rows(a: .selected, b: .active)
        #expect(
            EditorSelection.proposed([0, 2], current: [0, 2], lastSelected: 0, rows: current)
                .isEmpty)
    }

    @Test func anEmptyProposalMakesNoCalls() {
        #expect(
            EditorSelection.proposed([], current: [0], lastSelected: nil, rows: rows(a: .active))
                .isEmpty)
    }

    @Test func selectedRowsAreTheSelectedSegmentsAndGroups() {
        let state = rows(b: .selected, c: .active, group: true)
        #expect(EditorSelection.selectedRows(state) == [1, 2, 3])
        #expect(EditorSelection.selectedRows(rows(a: .active)) == [0])
        #expect(EditorSelection.selectedRows(rows()).isEmpty)
    }
}
