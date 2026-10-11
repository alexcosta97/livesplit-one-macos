## Settings

The app keeps its settings in one file:

    ~/Library/Application Support/livesplit-one-macos/app.toml

Your splits and layouts stay wherever you keep them; the app only stores where they are.

It holds the window's position and size for each layout, **Always on Top**, what a reset with new best times does, and any keyboard shortcuts you changed. The file is created the first time a setting changes and rewritten each time one does. The app writes it once the move or resize ends, not on every step. It is a [TOML](https://toml.io) text file, so you can read it, but quit the app before editing it: the app reads it only when it starts, and rewrites it when a setting changes.

If the app can't read the file, for example after a mistake while editing it, it starts with the default settings and keeps the old file next to it as `app.toml.bad`, so nothing is lost. Each time this happens, the previous `app.toml.bad` is replaced. If the app can't keep the old file either, for example because the folder is read-only, it leaves the file as it is and doesn't save setting changes until it restarts.

## The Settings window

Choose **Settings…** in the right-click menu or the **LiveSplit One** menu, or press ⌘,. Every change is saved at once.

<!-- screenshot: S8 settings-window.png -->
The Settings window, with two shortcuts for Start/Split.

### General

**When a reset has new best times** decides what **Reset** does after an attempt beat some of your best times:

- **Ask**: until the app can ask you, which comes with opening and saving splits, it updates them.
- **Update them**: the attempt's best times replace the old ones.
- **Keep the old ones**: the attempt is reset and your best times stay as they were.

### Shortcuts

Each command of the **Control** menu, with its keys.

- **+** adds a key: press the key, with ⌃, ⌥, ⇧ or ⌘ if you want them. Esc cancels. A key the app can't use makes a beep, and the window keeps waiting for a key.
- Click a key to remove it.
- A command can have several keys, and any of them runs it.
- A key another command already uses isn't added; the window says which command has it. ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘, and ⌘W are kept for the app's menus.
- macOS keeps some keys for itself, such as ⌃Space for switching input sources. The window never sees those, so they can't be added; change them in System Settings → Keyboard → Keyboard Shortcuts if you need them.
- **Restore Defaults** puts back the keys in [The Timer Window](The-Timer-Window#keyboard-shortcuts).

## Logs

The app records what it does in log files, one per day:

    ~/Library/Logs/livesplit-one-macos/livesplit-one-macos-YYYY-MM-DD.log

- Files older than 7 days are deleted when the app starts and when a new day's file begins.
- Once a day's file reaches 50 MB, only errors are written to it until the next day, after one line saying so.
- Each line starts with the time, to the millisecond, and what the line is about: **ERROR**, **CONNECTION** (connecting to a server, its commands and the app's replies), **TIMER** (timer actions and where they came from) or **APP** (the app starting, settings, files opened and saved).

For example:

    19:31:01.254  APP  LiveSplit One for macOS 0.1.0 started on macOS 15.1.0

If the app can't write a log file, it keeps running, stops writing log files until it restarts, and the lines still go to the system log.

### Finding the logs

- Choose **Open Log Folder** in the right-click menu or the **Help** menu.
- In Finder, choose **Go → Go to Folder…** and paste `~/Library/Logs/livesplit-one-macos`.
- **Console.app** lists the files under **Log Reports**.
- Console.app's live stream also shows every line as it happens, next to macOS's own messages, such as whether the app was allowed local network access. Search for the subsystem `dev.alexcosta.livesplit-one-macos`.
