Right-click anywhere in the timer window to open its menu. While the app is in front, the same commands are also in the menu bar at the top of the screen.

<!-- screenshot: S2 right-click-menu.png -->
The right-click menu, with Control open.

| Item | What it does |
|---|---|
| **Edit Splits…** | Opens the splits editor: see [Editing Splits](Editing-Splits). |
| **Open Splits** | Opens splits from a file or the recent files, below. |
| **Save Splits** (⌘S) | Saves the splits to their file. |
| **Save Splits As…** (⇧⌘S) | Saves the splits to a file you choose. |
| **Close Splits** | Goes back to a new run, with the layout kept. |
| **Control** | The timer's commands, below. |
| **Compare Against** | The comparison the timer shows, and Real Time or Game Time, below. |
| **Open Layout** | Opens a layout from a file or the recent files, below. |
| **Save Layout As…** | Saves the layout to a `.ls1l` file you choose. |
| **Connect to Server…** | Connects to a timer server, such as livesplit-asr-bridge. Reads **Disconnect from &lt;host&gt;** while connected, connecting or retrying, and closes the connection. See [Connecting to a Server](Connecting-to-a-Server). |
| **Always on Top** | Keeps the timer window above other apps' windows. A tick shows when it's on. The app remembers it. |
| **Settings…** | Opens the Settings window. See [Settings and Logs](Settings-and-Logs#the-settings-window). |
| **Open Log Folder** | Opens the folder with the app's logs in Finder. See [Settings and Logs](Settings-and-Logs#logs). |
| **About LiveSplit One for macOS** | Shows the app's version. |
| **Quit** | Quits the app. |

An item that can't be used right now is greyed out.

## Files

**Edit Splits…** is greyed out while an attempt is running, paused or finished and not reset yet. **Open Splits** and **Open Layout** each open a list: **Open…**, then the recent files, the newest first, and **Clear Menu** below them. **Open Splits**, its recent files, its **Clear Menu** and **Close Splits** are greyed out while an attempt is running, paused or finished and not reset yet. While the splits editor is open, the timer's menus can't be used: see [Editing Splits](Editing-Splits#while-the-window-is-open). What each item does, and the format each file uses, is in [Splits and Layouts](Splits-and-Layouts).

## Control

| Item | What it does | Greyed out |
|---|---|---|
| **Start**, or **Split** while the timer runs | Starts the timer, or ends the current segment. | While paused, and once the run has ended. |
| **Reset** | Ends the attempt and stops the timer. If the attempt beat some of your best times, the app asks whether to update them, or does what you chose in Settings: see [Splits and Layouts](Splits-and-Layouts#reset-with-new-best-times). | Before the timer starts. |
| **Undo Split** | Goes back to the previous segment, or reopens the last one after the run ended. | Before the first split. |
| **Skip Split** | Moves to the next segment without a time for this one. | On the last segment, and when the timer isn't running or paused. |
| **Pause**, or **Resume** while paused | Pauses or resumes the timer. | When the timer isn't running or paused. |
| **Undo All Pauses** | Removes the paused time from the attempt, and resumes if paused. | Before the timer starts. |

Each one also has a keyboard shortcut. See [The Timer Window](The-Timer-Window#keyboard-shortcuts).

## Compare Against

Lists your run's comparisons, your own first, then **Personal Best**, **Best Segments** and the others LiveSplit One has. A tick shows the one the timer compares against. Below them, **Real Time** and **Game Time** choose the timing method.

## The menu bar

The menu bar has the same commands, in the places Mac apps keep them:

- **LiveSplit One**: **About LiveSplit One for macOS**, **Settings…** (⌘,), **Hide LiveSplit One for macOS** (⌘H), **Hide Others** (⌥⌘H), **Show All**, **Quit LiveSplit One for macOS** (⌘Q).
- **File**: **Edit Splits…**, **Open Splits**, **Save Splits** (⌘S), **Save Splits As…** (⇧⌘S), **Close Splits**, then **Open Layout** and **Save Layout As…**, then **Connect to Server…**, as above.
- **Edit**: **Undo** (⌘Z), **Redo** (⇧⌘Z), **Cut** (⌘X), **Copy** (⌘C), **Paste** (⌘V) and **Select All** (⌘A). They work in the text fields of the splits editor and the Connect to Server sheet. macOS adds its own items to this menu, such as AutoFill, Start Dictation and Emoji & Symbols.
- **Control** and **Compare Against**, as above.
- **Window**: **Close** (⌘W, for the Settings window), **Minimize** (⌘M), **Always on Top**.
- **Help**: **Open Log Folder**.
