The splits editor changes the run: its game, category, segments, times and comparisons. Right-click the timer and choose **Edit Splits…**, the first item under the splits items. It is also first in the **File** menu.

<!-- screenshot: S5 splits-editor.png -->
The **Edit Splits** window, with a custom comparison.

The window edits a copy of your splits. Nothing changes until you click **OK**.

## OK and Cancel

- **OK** (or Return) replaces the timer's splits with the edited ones. The splits are marked unsaved only if something changed: **OK** with no edits leaves them as they were. Save them as usual: see [Splits and Layouts](Splits-and-Layouts#saving-splits).
- **Cancel** (or Escape) throws the edits away. So does the close button. Escape cancels the whole window even while you are typing in a cell.

If you are typing in a cell when you click **OK**, the app applies what you typed first. If that is an invalid time, the window stays open: see [Invalid times](#invalid-times).

### While an attempt is in progress

**Edit Splits…** is greyed out during an attempt: see [The Menu](The-Menu#files). Reset first (**Reset** in [The Menu](The-Menu#control)).

A server can start an attempt while the window is open. **OK** then can't replace the splits without dropping the attempt, and says so under the table: **The splits can't change while an attempt is in progress. Reset it, or choose Cancel.** The window stays open with your edits. Reset the timer, then click **OK**, or choose **Cancel**.

### While the window is open

Nothing else can change the splits meanwhile: see [The Menu](The-Menu#files). **Quit** does nothing until you close the window.

## Game and category

- The picture next to **Game:** is the game's icon: see [Icons](#icons).
- **Game:** and **Category:** are the names the splits show.
- **Start Offset:** is the time the timer starts at, such as `-0:03`.
- **Attempts:** is the number of attempts. It takes a whole number.

## The layout the splits use

**Layout:** sets which layout opens with these splits. It lists:

- **None**: the splits name no layout.
- The layout showing now, by its file name, or **Default Layout**.
- The layout the splits already name, if it is another one.

The choice is saved with the splits, and the app opens that layout the next time you open them: see [Layouts that splits use](Splits-and-Layouts#layouts-that-splits-use). The timer keeps the layout it shows now.

## Segments

The table has a row for each segment. It starts with an icon column, then **Segment Name**, **Split Time**, **Segment Time** and **Best Segment**, then one column for each custom comparison.

Click a name or a time and type to edit it. Press Return to finish, or Tab to go to the next cell. Escape cancels the whole window.

| Button | What it does |
|---|---|
| **Insert Above** | Adds a segment above the selected one. |
| **Insert Below** | Adds a segment below the selected one. |
| **Remove Segment** | Removes the selected segments. |
| **Move Up** | Moves the selected segments up one place. |
| **Move Down** | Moves the selected segments down one place. |

A button is greyed out when it can't be used, for example **Move Up** on the first segment.

### Selecting rows

- Click a row to select it.
- ⌘-click adds a row to the selection, or removes it.
- ⇧-click selects every row from the last one you clicked.
- Click a group's row to select all of its segments.

The buttons work on all the selected segments. A time is edited in the row you clicked last.

### Groups

A group puts segments under one name, such as a world or a chapter. Its row shows above its segments, which are indented. It has an icon and a name, and no times.

- **Create Group** makes the selected segments a group. They must be next to each other, and not already in a group.
- **Remove Group** turns the selected groups back into plain segments. The segments stay.
- Edit a group's name and icon in its row. If you leave the name empty, the group takes the name of its last segment, shown in grey.

### Times

**Split Time** is the time on the clock at the end of the segment, **Segment Time** is how long the segment took, and **Best Segment** is the shortest time you have had for it. Type a time such as `1:23.45`.

**Real Time** and **Game Time**, under the table, choose which times the table shows and edits. See [The Menu](The-Menu#compare-against) for the timing method the timer uses.

An empty time in the table clears it.

### Invalid times

If a time or **Start Offset:** isn't a time, the cell turns red and keeps the cursor, and a line under the table says **Enter a time, such as 1:23.45.** If **Attempts:** isn't a whole number, the line says **Enter a whole number.** An empty start offset or attempt count is also refused. Type a valid value, or choose **Cancel**, to go on. Only the times in the table can be left empty. **OK** doesn't close the window while one is wrong.

## Comparisons

The table shows your own comparisons in columns after **Best Segment**.

- **Add Comparison…** asks for a name, then adds a comparison with that name.
- **Rename Comparison** lists your comparisons. Choose one and change its name.
- **Remove Comparison** lists your comparisons. Choose one to remove it.

Both **Rename Comparison** and **Remove Comparison** are greyed out while you have none. The comparisons LiveSplit One has itself, such as **Personal Best**, can't be renamed or removed.

A name that another comparison uses, or that starts with `[Race]`, is refused: the question stays open and says **That name is already used, or starts with [Race].**

## Icons

Click the picture for the game, or for a segment or a group, and choose:

- **Choose Image…** to pick an image file.
- **Remove Image** to take the icon away. It is greyed out when there is none.

The file can be a PNG, JPEG, GIF, BMP, TIFF, WebP or ICO, up to 16 MB. If it can't be used, an alert says **Couldn't use "&lt;file&gt;" as an icon.** with the reason, or **It isn't an image LiveSplit One for macOS can read.**

## Other

**Other** has two items, and each asks you to confirm:

| Item | What it removes |
|---|---|
| **Clear History…** | Every attempt, and every segment's history. Your personal best and your best segments stay. |
| **Clear Times…** | The history, every time, the attempt count and your custom comparisons. |

Neither changes anything until you click **OK** on the window, and **Cancel** brings everything back.

## What isn't here

This version doesn't edit speedrun.com details (region, platform and variables), Clean Sum of Best, custom variables or auto splitter settings. It can't import or generate comparisons, or move them.
