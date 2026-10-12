Your splits are the run: its game, segments and times. Your layout is how the timer looks. The app keeps them in separate files, as LiveSplit One does, and opens, saves and closes them from the **File** menu in the menu bar, or from the right-click menu, which has the same items. See [The Menu](The-Menu).

Your files stay where you keep them. The app only remembers where they are: see [Settings and Logs](Settings-and-Logs#settings).

## Opening splits

Choose **Open Splits** then **Open…**, and pick a file. Any format LiveSplit One reads opens: LiveSplit's `.lss`, and the formats of splits.io, Llanfair, WSplit and others. The file doesn't need to end in `.lss`.

If the current splits have unsaved changes, the app asks about them first, before the file is chosen: see [Unsaved changes](#unsaved-changes).

If the file opens, the timer shows its run, and the app opens the layout the splits use, if they name one: see [Layouts that splits use](#layouts-that-splits-use). If it doesn't, a message says why and the timer is left as it was: see [When a file doesn't open](#when-a-file-doesnt-open).

## Opening a layout

Choose **Open Layout** then **Open…**, and pick a `.lsl` file (LiveSplit's layouts) or a `.ls1l` file (LiveSplit One's layouts). The timer shows it at once, and keeps your splits.

The window keeps its position and size for each layout. A layout you open for the first time keeps the window's size until the layout asks for another. See [The Timer Window](The-Timer-Window#size-and-position).

## Recent files

**Open Splits** and **Open Layout** each list the last 10 files you opened or saved, the newest first. Choose one to open it. Rest the pointer on one to see where it is.

Two files with the same name in different folders also show the name of the folder they're in, such as **Splits.lss — Races**.

**Clear Menu**, at the bottom of the list, empties it. It doesn't delete any file.

## Saving splits

- **Save Splits** (⌘S) saves the run to its file.
- **Save Splits As…** (⇧⌘S) asks where to save it, and the run's file becomes the new one.

The app always saves splits as `.lss`, LiveSplit's own format, whatever the file was when you opened it. So when the splits came from another format, or have no file yet, **Save Splits** asks for a name, rather than writing `.lss` over a file that isn't one. The name it suggests is the file's own name with `.lss`, or the game and category for a new run.

If the app can't save the file, an alert says why, and the splits stay marked as unsaved.

## Closing splits

**Close Splits** goes back to a new run with one segment, **Time**, as when the app first opens. The layout stays. The app asks about unsaved changes first, and doesn't reopen the splits at the next launch.

## Unsaved changes

When the splits have unsaved changes, opening other splits, **Close Splits** and **Quit** ask first:

<!-- screenshot: S6 unsaved-changes.png -->
The alert "Do you want to save the changes to "Splits.lss"?", with Save, Don't Save and Cancel.

- **Save** saves the splits, then goes on. If the splits have no file yet, or a file that isn't `.lss`, it asks for a name, and **Cancel** there stops what you were doing.
- **Don't Save** goes on without saving.
- **Cancel** does nothing.

A finished attempt counts as a change, as in LiveSplit, and so does a reset: they add to the splits' history, which is saved with them.

If an attempt is in progress when you quit, the app resets it first, as LiveSplit does when it closes. The attempt then counts as a change and is asked about like any other. If the reset has new best times, the question below comes first.

## Why Open Splits is greyed out

**Open Splits**, its recent files, its **Clear Menu** and **Close Splits** are greyed out while an attempt is running, paused, or finished and not reset yet. Replacing the splits then would throw the attempt away. Reset first (**Reset** in [The Menu](The-Menu#control)), then open the splits. **Open Layout** isn't affected, so you can change the layout in the middle of an attempt.

## Reset with new best times

When you reset an attempt that beat some of your best times, the app asks whether to update them:

<!-- screenshot: S7 reset-new-best.png -->
The alert "Do you want to update your best times?", with Yes, No and Don't Reset.

- **Yes** updates the best times, and resets.
- **No** resets and keeps the old best times.
- **Don't Reset** leaves the attempt as it was.

**Yes** and **No** are remembered as your answer, so the app asks only once. To change it later, open **Settings…**: [Settings and Logs](Settings-and-Logs#general) describes the choice. **Don't Reset** isn't remembered.

## Layouts that splits use

Splits saved by LiveSplit can name the layout they are used with. When you open such splits from the menu, the app opens that layout too. If they point to the default layout, the timer shows the default layout.

If that layout can't be opened, the one you had stays, and a notice names the file: see [The Timer Window](The-Timer-Window#notices).

The app never changes which layout splits use: it opens the layout and doesn't write the link back.

## Saving a layout

**Save Layout As…** saves the layout as a `.ls1l` file, LiveSplit One's format. It is the only layout format the app can write. For a layout you opened from a `.lsl`, the name suggested is the same with `.ls1l`, so your `.lsl` is never overwritten. The window then shows the new file, with the position and size it has now.

If the app can't save the file, an alert says why.

## What opens at launch

The app reopens the splits and the layout you last had open, and the window where you left it.

If one of them can't be opened, for example because it was on a drive that isn't connected, the timer shows a notice:

**Couldn't reopen "Splits.lss": &lt;reason&gt;**

and the app uses the default layout, or a new run. The app doesn't forget the file, so when the drive is back, the next launch reopens it. See [Troubleshooting](Troubleshooting#a-file-didnt-reopen-at-launch).

If the splits you had open name a layout, the layout you last had open is reopened, not the one they name, because it is the one that was showing.

## When a file doesn't open

An alert says why, and your current splits and layout stay as they were:

| Alert | Why |
|---|---|
| **"&lt;name&gt;" isn't splits LiveSplit One for macOS can read.** | The file isn't in a format of splits that LiveSplit One reads, or it's empty. |
| **"&lt;name&gt;" isn't a layout LiveSplit One for macOS can read.** | The file isn't a `.lsl` or `.ls1l` layout. |
| macOS's own reason | macOS couldn't read the file: it's missing, or you have no permission to read it. |
| **It isn't a regular file.** | Splits and layouts have to be files, not folders or devices. |
| **It's too large to be a splits or layout file.** | The app opens files up to 64 MB. Real splits and layouts are a few kilobytes. |

The app can't tell a file that is damaged from one that isn't splits, so both get the same message.
