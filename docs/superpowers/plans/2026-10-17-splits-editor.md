# Splits Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The splits editor from spec §9 (issue #15): a modal **Edit Splits** window over livesplit-core's `RunEditor`, with the game details, the linked layout, the segment table with segment groups, the segment, group and comparison buttons, the timing method switch and **Other ▸**, applied with OK through `TimerContent.setRun(_:)`.

**Architecture:** `RunEditorState` decodes `RunEditor.stateAsJson`. `SplitsEditing` owns the `RunEditor`, its own `ImageCache` and the language; it is the only code that calls `RunEditor`, and after each call it decodes the state again. `EditorSelection` turns a click or a table's proposed selection into `RunEditor` selection calls. `SplitsEditorViewController` (the header, the table, the buttons) holds no state but the linked layout (spec §9): every action calls `SplitsEditing`, then redraws from its `state`. Questions (names, confirmations, images) go through `SplitsEditorPrompts`, so headless tests script them. `SplitsEditorPresenter` runs the window modally and applies OK through `TimerContent.setRun(_:)`. `TimerMenus` adds **Edit Splits…** to both menus, and the menu bar gets an Edit menu.

**Tech Stack:** Swift 6, AppKit (`NSTableView` view-based, `NSTextField`, `NSSegmentedControl`, `NSPopUpButton`, `NSAlert`, `NSApp.runModal(for:)`), livesplit-core's `RunEditor`, `ImageCache`, `LinkedLayout` through the generated bindings, Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md`, sections 7 and 7.1 (changed by this plan's pull request: Edit Splits' enabling and place in the File menu, the Edit menu, the link wording), 9 (rewritten by it), 12.1, 14 and 16.2. Issue: #15, with its comments (from #67 and #68).

**Branch and worktree:** `feat/splits-editor`, at `../livesplit-one-macos-wt/splits-editor`, from `main`. **PR title:** `feat: add the splits editor`. **PR body:** `Closes #15`, from the pull request template. One pull request for the whole plan; each task is one commit.

## Before you start

- Read `CONTRIBUTING.md`, the spec sections above and both comments on #15. Run the checks in `CONTRIBUTING.md` step 4 on `main` once.
- Read `App/TimerWindow/TimerContent.swift`, `App/Files/FileController.swift`, `App/Files/FileLoadError.swift`, `App/Files/FilePicker.swift`, `App/Files/FileAlerts.swift`, `App/Menu/TimerMenus.swift`, `App/Menu/TimerCommand.swift` (`TimingMethod`), `App/AppDelegate.swift`, `App/Server/ConnectSheet.swift`, `Tests/HeadlessUI/ConnectSheetTests.swift`, `Tests/HeadlessUI/TimerMenusTests.swift`, `Tests/E2E/E2EApp.swift` and `Tests/E2E/FileTests.swift`.
- Read livesplit-core's editor at the pinned revision (`core/Cargo.toml`): `src/run/editor/mod.rs` and `state.rs` in `~/.cargo/git/checkouts/livesplit-core-*/61070c4/`, and `capi/src/run_editor.rs`. The generated Swift is in `LiveSplitCore/Generated/LiveSplitCore.swift` after `scripts/build-core.sh` (class `RunEditor`, `RunEditorRefMut`).
- Shell setup on the maintainer's Mac: `export PATH="$(brew --prefix rustup)/bin:$HOME/.cargo/bin:$PATH"`, then `mise install`. After adding Swift files, run `xcodegen generate`.
- Run one suite with `xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:<Target>/<SuiteName>`.

## Global Constraints

- **`RunEditor` decides.** Swift never checks a name, a time or a selection rule itself; it calls `RunEditor` and redraws from its state (spec §9). Buttons are enabled from `state.buttons` and from what the state shows (no custom comparisons: Rename and Remove Comparison disabled).
- **One way in.** OK replaces the run only through `TimerContent.setRun(_:)` (#15's first comment), on the main thread under the timer's write lock (#15's second comment). The app writes the linked layout only through `RunEditor.setLinkedLayout` / `removeLinkedLayout`, from the **Layout:** pop-up.
- **The editor's `ImageCache` is its own**, separate from `TimerContent.imageCache`; call `collect()` after each state read.
- **Texts, exactly** (spec §9):
  - Window title **Edit Splits**; buttons **OK** (default, Return), **Cancel** (Escape).
  - Labels **Game:**, **Category:**, **Start Offset:**, **Attempts:**, **Layout:**; pop-up items **None**, the current layout's file name or **Default Layout**, and the linked one's file name when it is another.
  - Table headers **Icon** (shown empty), **Segment Name**, **Split Time**, **Segment Time**, **Best Segment**, then each custom comparison's name.
  - Buttons **Insert Above**, **Insert Below**, **Remove Segment**, **Move Up**, **Move Down**, **Create Group**, **Remove Group**, **Add Comparison…**, pull-downs **Rename Comparison**, **Remove Comparison**, **Other**; switch **Real Time** / **Game Time**.
  - Invalid input: **Enter a time, such as 1:23.45.**, **Enter a whole number.**
  - Attempt in progress on OK: **The splits can't change while an attempt is in progress. Reset it, or choose Cancel.**
  - Name questions: **Add Comparison** / **Rename Comparison** (prefilled), buttons **OK** and **Cancel**; refused name: **That name is already used, or starts with [Race].**
  - **Clear the history?** / *This removes every attempt and every segment's history. The personal best and the best segments stay.* / **Clear History**, **Cancel**.
  - **Clear the times?** / *This removes the history, every time, the attempt count and the custom comparisons.* / **Clear Times**, **Cancel**.
  - Icon menu: **Choose Image…**, **Remove Image**. Icon that can't be used: **Couldn't use "<file>" as an icon.** with the reason, or *It isn't an image LiveSplit One for macOS can read.*
- **Accessibility identifiers:** `splits-editor` (window), `editor-ok`, `editor-cancel`, `editor-game-icon`, `editor-game`, `editor-category`, `editor-offset`, `editor-attempts`, `editor-layout`, `editor-segments` (table), cells `editor-cell-<column>-<row>` with columns `icon`, `name`, `split`, `segment`, `best`, `comparison-<index>`; buttons `editor-insert-above`, `editor-insert-below`, `editor-remove`, `editor-move-up`, `editor-move-down`, `editor-create-group`, `editor-remove-group`, `editor-add-comparison`, `editor-rename-comparison`, `editor-remove-comparison`, `editor-timing-method`, `editor-other`; message `editor-message`. Menu item `timer-edit-splits` (right-click only: the menu bar's items have no identifiers, as #12 has it).
- **Log lines** (spec §12.1): `TIMER` `Edited the splits` when OK replaced a changed run; `ERROR` `Couldn't apply the splits editor's changes: an attempt is in progress`. Nothing for Cancel or an unchanged OK.
- Icons: `ImageFile.sizeLimit = 16 * 1024 * 1024`; the open panel allows `png`, `jpeg`, `gif`, `bmp`, `tiff`, `webp`, `ico` (the formats livesplit-core's `image-shrinking` and `rendering` features decode).

## Review Focus

1. **OK while a field is being edited.** Typing a new name and pressing Return (OK) must apply that name; with an invalid time in the field, OK must not close the window. OK first ends editing (`window.makeFirstResponder(nil)`) and stops if it returns `false`. Test in Task 7.
2. **An attempt started while the editor is open** (server `splitOrStart`): OK keeps the window and the edits, shows the message, and the attempt runs on. `close()` consumes the editor, so on `.attemptInProgress` reopen `SplitsEditing` from the returned run. Tests in Task 8.
3. **Redrawing during Tab navigation.** After a cell edit commits and Tab starts editing the next cell, the redraw must not end that edit. Refresh updates views in place unless rows or columns changed (Task 6). Test in Task 6.
4. **Row indexes are not segment indexes** once a group exists. Every call uses `segmentIndex` / `groupIndex` from the state's rows. Tests in Tasks 1 and 6 with a grouped run.
5. **Nothing else replaces the run while the editor is open:** Edit Splits, Open Splits, its recent files and Close Splits are disabled, and Quit is refused, so OK never overwrites a run opened meanwhile. Tests in Task 8.

## Spec changes this pull request makes

Commit the rewrite of §9 and the §7 and §7.1 changes (made when this plan was written) with the plan. If the work shows the spec is wrong, fix it in this pull request and list the change in the description.

## Left to later issues

Post each as a comment on the issue named once the pull request is open, and list them in the description:

- **#41:** screenshot S5 (`splits-editor.png`, the editor with a custom comparison) for Editing Splits.
- **#18:** the Edit Splits flow from §14.3 is added by Task 8; tick it on #18.
- **#66:** the icon reader (`ImageFile.read`) is what #66's icons for WSplit, SplitterZ and FaceSplit can use.

---

### Task 1: `RunEditorState` and `SplitsEditing`

**Files:**
- Create: `App/SplitsEditor/RunEditorState.swift`, `App/SplitsEditor/SplitsEditing.swift`
- Create: `Tests/Fixtures/Grouped.lss` (three segments `A`, `B`, `C` with `B` and `C` in a group named `Last`, a custom comparison `Goal`, and a game icon; make it once with `RunEditor` in a scratch test, save with `saveAsLss`, and commit it)
- Test: `Tests/Unit/RunEditorStateTests.swift`, `Tests/Unit/SplitsEditingTests.swift`

```swift
/// `RunEditor`'s state, as `stateAsJson` encodes it (livesplit-core's `run/editor/state.rs`).
struct RunEditorState: Decodable, Equatable {
    var icon: String            // an image id; `ImageCache` has no data for an empty icon
    var game: String
    var category: String
    var offset: String
    var attempts: UInt32
    var timingMethod: TimingMethod   // decoded from "RealTime" / "GameTime"
    var rows: [Row]
    var comparisonNames: [String]
    var buttons: Buttons

    struct Buttons: Decodable, Equatable {
        var canRemove, canMoveUp, canMoveDown, canCreateSegmentGroup, canRemoveSegmentGroups: Bool
    }
    enum Selection: String, Decodable { case notSelected = "NotSelected", selected = "Selected", active = "Active" }
    struct Segment: Decodable, Equatable {
        var segmentIndex: Int; var icon: String; var name: String
        var splitTime, segmentTime, bestSegmentTime: String
        var comparisonTimes: [String]; var selected: Selection; var isIndented: Bool
    }
    struct Group: Decodable, Equatable {
        var groupIndex: Int; var name: String; var explicitName: String?
        var icon: String; var hasExplicitIcon: Bool; var selected: Bool
    }
    /// Tagged by `"kind"`: `"Segment"` or `"SegmentGroup"`.
    enum Row: Decodable, Equatable { case segment(Segment), group(Group) }
}
```

Decode with `keyDecodingStrategy = .convertFromSnakeCase`; `metadata` is ignored.

```swift
/// The run being edited (spec §9): the only code that calls `RunEditor`.
@MainActor
final class SplitsEditing {
    init(run: Run, lang: UInt8 = TimerContent.systemLanguage)  // RunEditor(run)!: the run has segments
    private(set) var state: RunEditorState
    /// The icon for an image id, or nil for the empty image.
    func image(_ id: String) -> NSImage?
    /// The edited run. The object can't be used after.
    func finish() -> Run

    // Each call below goes to RunEditor, then reads `state` again.
    func setGame(_ name: String); func setCategory(_ name: String)
    func setOffset(_ text: String) -> Bool; func setAttempts(_ text: String) -> Bool
    func setGameIcon(_ data: Data); func removeGameIcon()
    func setLinkedLayout(_ link: LinkedLayoutTarget)   // .none → removeLinkedLayout; .defaultLayout → LinkedLayout("")
    func selectTimingMethod(_ method: TimingMethod)
    func apply(_ selection: [EditorSelection.Call])    // Task 2's type
    func insertAbove(); func insertBelow(); func removeSegments(); func moveUp(); func moveDown()
    func createGroup() -> Bool; func removeGroups() -> Bool
    func renameGroup(_ index: Int, _ name: String)     // "" gives the group its last segment's name
    func setGroupIcon(_ index: Int, _ data: Data); func removeGroupIcon(_ index: Int)
    /// Makes `segment` active, keeping the selection, then sets the field. `false` if it doesn't parse.
    func setName(_ name: String, segment: Int)
    func setTime(_ column: TimeColumn, _ text: String, segment: Int) -> Bool
    func setSegmentIcon(_ data: Data, segment: Int); func removeSegmentIcon(segment: Int)
    func addComparison(_ name: String) -> Bool
    func renameComparison(_ old: String, to new: String) -> Bool
    func removeComparison(_ name: String)
    func clearHistory(); func clearTimes()
}

enum TimeColumn: Equatable { case split, segment, best, comparison(String) }
```

`setTime`/`setName`/the segment icon calls first call `selectAdditionally(segment)` when that segment isn't `.active` (it makes it active and keeps the others selected). Times parse with `lang`. Icons are passed as `data.withUnsafeBytes` pointer and count.

- [ ] **Tests first** (`RunEditorStateTests`): decode the JSON of `TimerContent.defaultRun()`'s editor: one `.segment` row named `Time`, `.active`, timing `.realTime`, `canRemove` false. Decode `Grouped.lss`: rows are `A`, group `Last`, `B`, `C`; `B`'s `segmentIndex` is 1 at row 2; `comparisonNames == ["Goal"]`.
- [ ] **Tests first** (`SplitsEditingTests`, real livesplit-core): `setTime(.split, "1:00", segment: 0)` → `true`, row shows `1:00.00`; `"abc"` → `false`, state unchanged; `""` clears it; `setAttempts("x")` → `false`; `addComparison("Goal")` twice → second `false`; `addComparison("[Race] x")` → `false`; `insertBelow()` then `finish().len() == 2`; on `Grouped.lss` `setName("Z", segment: 2)` renames `C` (row 3); `renameGroup(0, "")` → the group's `name` is `C`, `explicitName` nil; `image(state.icon)` is non-nil for `Grouped.lss` and nil for the default run; a new `SplitsEditing` → `finish().hasBeenModified()` is false, and true after `setGame("x")`.
- [ ] Implement. Run both suites. Pass.
- [ ] Commit: `feat(splits-editor): add the run editor model`

### Task 2: `EditorSelection`: clicks to `RunEditor` selection calls

**Files:**
- Create: `App/SplitsEditor/EditorSelection.swift`
- Test: `Tests/Unit/EditorSelectionTests.swift`

```swift
/// Turns what the table proposes into RunEditor's selection calls (spec §9), so the table's
/// selection is always the editor's.
enum EditorSelection {
    enum Call: Equatable {
        case only(Int), additionally(Int), unselect(Int), range(Int)                 // segment indexes
        case group(Int), toggleGroup(Int), groupRange(Int)                          // group indexes
    }
    enum Modifier { case none, command, shift }

    /// A click on `row` (a presentation row) with `modifier`.
    static func click(row: Int, modifier: Modifier, rows: [RunEditorState.Row]) -> [Call]
    /// A selection the table proposes with no click (arrow keys, ⇧-arrows, ⌘A): `proposed` and
    /// `current` are row indexes.
    static func proposed(_ proposed: IndexSet, current: IndexSet, rows: [RunEditorState.Row]) -> [Call]
    /// The rows the state shows selected: segments `.selected` or `.active`, groups `selected`.
    static func selectedRows(_ rows: [RunEditorState.Row]) -> IndexSet
}
```

- `click`: segment row: none → `.only`, command → `.unselect` if selected else `.additionally`, shift → `.range`. Group row: `.group`, `.toggleGroup`, `.groupRange`.
- `proposed`: one row → as a plain click. More rows, with one row added to `current`, contiguous with it → `.range(addedRow)`. Anything else (⌘A, a shrink): `.only(first segment)` then `.additionally` for each other proposed segment row, the table's last-selected row last, so it is active. Group rows in a proposal stand for their segments.

The table delegate's `tableView(_:selectionIndexesForProposedSelection:)` (Task 6) uses `click` when `NSApp.currentEvent` is a left mouse down on a row (`clickedRow`), `proposed` otherwise, applies the calls, and returns `selectedRows(state.rows)`.

- [ ] **Tests first:** on `Grouped.lss`'s rows: click row 0 → `[.only(0)]`; ⌘-click a selected row 3 → `[.unselect(2)]`; ⇧-click row 3 → `[.range(2)]`; click group row 1 → `[.group(0)]`; ⌘-click it → `[.toggleGroup(0)]`; proposal `{0,1,2,3}` from `{0}` → only and additionally calls covering 0, 1, 2; `selectedRows` with `B` and `C` selected and the group selected → `{1, 2, 3}`. Implement. Pass.
- [ ] Commit: `feat(splits-editor): map table selection to the run editor`

### Task 3: Icons from files

**Files:**
- Create: `App/Files/ImageFile.swift`
- Modify: `App/Files/FileLoadError.swift` (`readBounded` usable with another limit and its own too-large text), `App/Files/FilePicker.swift` (`FileKind.image`)
- Test: `Tests/Unit/ImageFileTests.swift`, `Tests/Unit/FilePickerTests.swift`

```swift
enum ImageFile {
    static let sizeLimit = 16 * 1024 * 1024
    /// The bytes of an image file the editor can use as an icon (spec §9).
    static func load(_ url: URL) throws(FileLoadError) -> Data
}
```

`load` reads with the same bounded, regular-files-only read as splits; too large gives `.unreadable("It's too large to be an icon.")`; data `NSImage(data:)` can't decode gives a new case `.notImage`, whose `message(file:)` is *It isn't an image LiveSplit One for macOS can read.* `FileKind.image` opens with the seven content types in Global Constraints and logs as "image".

- [ ] **Tests first:** a PNG written by the test loads; a text file → `.notImage`; a file over the limit (sparse, `truncate`) → too large; `/dev/zero` → not a regular file; the open panel for `.image` allows exactly the seven types. Implement. Pass.
- [ ] Commit: `feat(splits-editor): read icons from image files`

### Task 4: `SplitsEditorPrompts`

**Files:**
- Create: `App/SplitsEditor/SplitsEditorPrompts.swift`
- Test: `Tests/HeadlessUI/SplitsEditorPromptsTests.swift`

```swift
/// The questions the editor asks, so tests can answer them (spec §9).
@MainActor
protocol SplitsEditorPrompts: AnyObject {
    /// Asks for a name until `accept` returns true or the user cancels. `accept` false shows the refused-name text.
    func askName(title: String, prefill: String, accept: (String) -> Bool) -> Bool
    func confirm(_ question: Confirmation) -> Bool
    /// An image file to use, or nil.
    func chooseImage() -> URL?
    func showIconFailed(_ error: FileLoadError, file: String)
}
enum Confirmation { case clearHistory, clearTimes }
```

`SystemSplitsEditorPrompts(picker: FilePicker)` builds `NSAlert`s as `FileAlerts` does, with static builders the tests check (`nameAlert(title:prefill:)` with an `NSTextField` accessory, `confirmation(_:)`, `iconFailed(_:file:)`), and runs them sheet-free with `runModal()` (the editor window is modal already). `chooseImage` is `picker.fileToOpen(.image)`.

- [ ] **Tests first:** each builder's texts and button titles from Global Constraints; the confirmation's first button is the destructive one (`hasDestructiveAction`) and Escape is **Cancel**.
- [ ] Commit: `feat(splits-editor): add the editor's questions`

### Task 5: The editor view: header, layout, timing method, message

**Files:**
- Create: `App/SplitsEditor/SplitsEditorViewController.swift`, `App/SplitsEditor/IconButton.swift`
- Test: `Tests/HeadlessUI/SplitsEditorViewTests.swift`, `Tests/HeadlessUI/Support/ScriptedPrompts.swift` (answers names, confirmations and images from arrays; records calls)

```swift
@MainActor
final class SplitsEditorViewController: NSViewController, NSTextFieldDelegate {
    /// `currentLayout` is what the timer window shows (`TimerWindowController.layoutPath`, nil for the default).
    init(editing: SplitsEditing, linkedLayout: LinkedLayoutTarget, currentLayout: String?,
         prompts: SplitsEditorPrompts, ok: @escaping () -> Void, cancel: @escaping () -> Void)
    var editing: SplitsEditing      // replaced by the presenter after an attempt blocked OK (Task 8)
    /// Shows `text` in `editor-message`, or hides it.
    func showMessage(_ text: String?)
    /// Redraws everything from `editing.state` (Task 6 adds the table).
    func refresh()
}

/// A square button showing an icon, or an empty well. Click shows Choose Image… / Remove Image.
final class IconButton: NSButton { var onChoose: () -> Void; var onRemove: () -> Void; var icon: NSImage? }
```

Layout with Auto Layout, as `SettingsViewController`: `IconButton` (64 pt) at the top left; to its right a grid of **Game:**, **Category:**, **Start Offset:**, **Attempts:** fields and **Layout:** pop-up; the table (Task 6) fills the middle; the button rows (Task 7) below it; `editor-message` (system red) and **Cancel** / **OK** at the bottom. Minimum content size 640 × 420.

- Game and category: `setGame`/`setCategory` in `controlTextDidEndEditing`.
- Offset and attempts: in `control(_:textShouldEndEditing:)`: `setOffset`/`setAttempts`; on `false` make the text `.systemRed`, show the matching message, return `false` (keeps focus); on `true` clear both and return `true`.
- Icon: choose → `prompts.chooseImage()`, `ImageFile.load`, `setGameIcon`, or `showIconFailed`.
- **Layout:** items as in Global Constraints. The window keeps `linkedLayout` (spec §9's exception) and selects its item; choosing calls `editing.setLinkedLayout` and updates it. A link to the current layout is one item, not two.
- Real Time / Game Time: `NSSegmentedControl`, `selectTimingMethod`.

- [ ] **Tests first:** fields show the state of `Grouped.lss`; ending the game field's editing with `X` → `state.game == "X"`; offset `abc` → `textShouldEndEditing` false, red text, message **Enter a time, such as 1:23.45.**; then `1.5` → true, message hidden; attempts `-1` → **Enter a whole number.**; **Layout:** with a run linking `/a/Other.lsl` and current `/b/Dark.lsl` lists **None**, **Dark.lsl**, **Other.lsl** with **Other.lsl** selected; choosing **Dark.lsl** then `finish()` links `/b/Dark.lsl`; current nil lists **Default Layout**; choosing **None** removes the link; Game Time switch → `state.timingMethod == .gameTime`; icon choose with a scripted PNG sets the icon, with a text file calls `showIconFailed`; Remove Image clears it.
- [ ] Commit: `feat(splits-editor): add the editor's game details`

### Task 6: The segment table

**Files:**
- Create: `App/SplitsEditor/SegmentTable.swift` (data source and delegate, owned by the view controller)
- Modify: `App/SplitsEditor/SplitsEditorViewController.swift`
- Test: `Tests/HeadlessUI/SegmentTableTests.swift`

- View-based `NSTableView`, `allowsMultipleSelection`, `allowsEmptySelection = false`, no column reordering. Columns from Global Constraints; one per `comparisonNames` entry, rebuilt when the names change.
- Segment rows: `IconButton` (24 pt), editable name, editable times. Indented rows (`isIndented`) indent the name by 16 pt. Group rows: `IconButton` (its icon or the inherited one), an editable name field with `explicitName ?? ""` and `name` as the grey placeholder, empty time cells; bold.
- Editing: name and group name commit in `controlTextDidEndEditing` (`setName`, `renameGroup`); times in `control(_:textShouldEndEditing:)` with `setTime`, red text and **Enter a time, such as 1:23.45.** on `false`, as in Task 5.
- Selection through Task 2 (`selectionIndexesForProposedSelection`).
- `refresh()`: if the row kinds and count and the columns are as last drawn, set each visible cell's value and selection in place, skipping a field whose `currentEditor()` is not nil; otherwise `reloadData()`. Then select `EditorSelection.selectedRows`.

- [ ] **Tests first** (headless, `Grouped.lss`): four rows; row 1 is the group with placeholder `Last`; the `Goal` column exists; editing `editor-cell-split-0` to `1:00` → its text `1:00.00`; to `abc` → refused, red, message shown; ⌘-click simulation through `EditorSelection` leaves the table's selection equal to the state's; selecting the group row selects rows 1–3; renaming the group row to `` shows `C` greyed; editing row 2's name, then Tab into row 3's name: after the refresh row 3's field is still editing (Review Focus 3); adding a comparison through `editing` and `refresh()` adds a column.
- [ ] Commit: `feat(splits-editor): add the segment table`

### Task 7: Buttons, comparisons, Other, OK and Cancel

**Files:**
- Modify: `App/SplitsEditor/SplitsEditorViewController.swift`
- Test: `Tests/HeadlessUI/SplitsEditorButtonsTests.swift`

- Segment buttons call `SplitsEditing` and refresh; enabled from `state.buttons` (Insert always). **Create Group** / **Remove Group** from `canCreateSegmentGroup` / `canRemoveSegmentGroups`; a new group has no name (it shows its last segment's).
- **Add Comparison…**: `prompts.askName(title: "Add Comparison", prefill: "", accept: editing.addComparison)`. **Rename Comparison** and **Remove Comparison**: pull-down `NSPopUpButton`s listing `comparisonNames`, disabled when empty; rename asks with the old name prefilled and `accept: { editing.renameComparison(old, to: $0) }`; remove removes at once (Cancel discards it).
- **Other**: pull-down with **Clear History…** and **Clear Times…**, each after `prompts.confirm`.
- **OK**: `view.window?.makeFirstResponder(nil)`; if `false`, stop (an invalid field keeps focus). Else `ok()`. **Cancel** and Escape: `cancel()`.

- [ ] **Tests first:** default run: Remove Segment, Move Up, Move Down disabled; Insert Below → two rows, Remove enabled; Move Down on row 0 swaps names; select `A` and `B` in `Grouped.lss` (`B` is grouped) → Create Group disabled; select `A` alone → enabled, creates a group whose row shows `A`; select the group → Remove Group removes it, three rows remain; Add Comparison with scripted `Goal` then `Goal 2` → the prompt was asked twice and the `Goal 2` column exists; Rename `Goal` to `PB Goal`; Remove `Goal`; Clear Times with scripted `false` changes nothing, with `true` empties the times; OK with the game field holding typed text calls `ok` after the game is set (Review Focus 1); OK with `abc` in a time field doesn't call `ok`.
- [ ] Commit: `feat(splits-editor): add the editor's buttons`

### Task 8: The window, the menus, the Edit menu and the E2E flow

**Files:**
- Create: `App/SplitsEditor/SplitsEditorPresenter.swift`, `Tests/E2E/SplitsEditorTests.swift`
- Modify: `App/Menu/TimerMenus.swift`, `App/AppDelegate.swift`
- Test: `Tests/HeadlessUI/SplitsEditorPresenterTests.swift`, `Tests/HeadlessUI/TimerMenusTests.swift`

```swift
/// Opens the splits editor and applies OK (spec §9).
@MainActor
final class SplitsEditorPresenter {
    init(content: TimerContent, window: TimerWindowController, prompts: SplitsEditorPrompts,
         log: Log = .shared, runModal: @escaping (NSWindow) -> Void = { NSApp.runModal(for: $0) })
    private(set) var isOpen = false
    /// Edit Splits…: does nothing unless `FileController.canReplaceRun` and not already open.
    func open()
    /// What OK does; internal so tests can call it without a modal session.
    func applyOK()
}
```

- `open`: copies the run with `content.withRun { $0.clone() }`, reads the link (`content.linkedLayout`) and `window.layoutPath`, builds the view controller in an `NSWindow` (`[.titled, .closable, .resizable]`, title **Edit Splits**, id `splits-editor`, centred on the timer window's screen), `isOpen = true`, `runModal(window)`. The window's close button and `cancelOperation` are Cancel.
- `applyOK`: `let run = editing.finish()`; `let changed = run.hasBeenModified()`; `content.setRun(run)`:
  - `.replaced`: `NSApp.stopModal()`, close, `isOpen = false`; log `Edited the splits` if `changed`. `setRun` already calls `markChanged()` and collects images.
  - `.attemptInProgress`: `controller.editing = SplitsEditing(run: run)`, keep the link, `refresh()`, show the message, log the error line. The window stays open.
  - `.noSegments`: can't happen (`RunEditor` keeps one segment); `assertionFailure` and treat as `.attemptInProgress` without the message.
- Cancel: `stopModal()`, close, `isOpen = false`. Nothing else.
- `TimerMenus`: a `splitsEditor: SplitsEditorPresenter?` init parameter (default nil, as `connectionStatus` has a default). **Edit Splits…** first in the right-click menu (id `timer-edit-splits`) and first in the File menu, in the splits group with no separator after it (spec §7's order). `validateMenuItem`: Edit Splits, Open Splits' items and Close Splits are enabled only when `files.canReplaceRun && splitsEditor?.isOpen != true`.
- **Edit menu** in the menu bar after File: Undo (⌘Z, `undo:`), Redo (⇧⌘Z, `redo:`), separator, Cut (⌘X), Copy (⌘C), Paste (⌘V), Select All (⌘A), all target-less (first responder). The Settings recorder takes ⌘-keys first (`KeyRecorderView.performKeyEquivalent`), and `ShortcutKeys` takes Control shortcuts first in the timer window, so these keys aren't added to `Shortcuts.reserved`; check both still hold with the menu in place.
- `AppDelegate`: makes the presenter with `SystemSplitsEditorPrompts(picker: picker)` (the same `FilePicker` as `FileController`), passes it to `TimerMenus`, and `applicationShouldTerminate` returns `.terminateCancel` while `isOpen`.

- [ ] **Tests first** (`SplitsEditorPresenterTests`, `runModal` a no-op): open, `setGame("X")`, `applyOK()` → the timer's run game is `X`, `content.hasUnsavedChanges`, log line written; open, `applyOK()` with no edits → not unsaved, no line; start an attempt on the timer while open, then `applyOK()` → run unchanged, `isOpen` true, message shown, edits still in `controller.editing.state`; Cancel → run unchanged; `open()` twice opens once; `open()` with an attempt in progress does nothing.
- [ ] **Tests first** (`TimerMenusTests`): **Edit Splits…** is first in both menus, disabled while running and while `isOpen`; Open Splits and Close Splits disabled while `isOpen`; the Edit menu's items and key equivalents.
- [ ] **E2E** (`SplitsEditorTests`, spec §14.3, one main-path test each, with `E2EApp`):
  - [ ] *OK:* launch with picks `[saved:Edited.lss]` (`FileTests`' `launched(picks:)` helper; move it to `E2EApp` if both suites need it). Right-click → **Edit Splits…**. Double-click `editor-cell-name-0`, type `First`, Tab, type `1:23.45` in the split time, Return in the field, click **OK**. Save Splits As… to `Edited.lss`. The file has `<Name>First</Name>` and a split time `00:01:23.45`.
  - [ ] *Cancel:* the same edits, then Escape. Save Splits As… writes `<Name>Time</Name>` and no `00:01:23.45`.
- [ ] Commit: `feat(splits-editor): open the splits editor from the menus`

### Task 9: The wiki, every check, and the pull request

**Files:**
- Create: `docs/wiki/Editing-Splits.md` (spec §16.2: game details, the linked layout, segments and groups, selecting rows, times and what an invalid one does, comparisons, Real Time and Game Time, Clear History and Clear Times, OK and Cancel, and why Edit Splits is sometimes disabled), with `<!-- screenshot: S5 splits-editor.png -->`
- Modify: `docs/wiki/_Sidebar.md` (after Splits and Layouts, per §16.2), `docs/wiki/Home.md` (link), `docs/wiki/The-Menu.md` (Edit Splits… in both menus and when it is disabled; the Edit menu), `docs/wiki/Splits-and-Layouts.md` (linked layouts: link one in the editor), `docs/wiki/Getting-Started.md` (a line pointing to Editing Splits for renaming segments)

- [ ] Write the pages. There is no full release yet, so they change directly (spec §16.3). Check every bold name against `App/`. Run `scripts/wiki/check.sh docs/wiki`.
- [ ] Try it by hand with the maintainer's own splits: icons, a grouped run made in LiveSplit One, OK and reopening the saved file in LiveSplit One in Chrome. Write what was seen in the pull request.
- [ ] Run every check in `CONTRIBUTING.md` step 4. Commit `docs: document the splits editor`, push, open the pull request from the template, listing the spec changes, the later-issue comments and screenshot S5 for #41.
