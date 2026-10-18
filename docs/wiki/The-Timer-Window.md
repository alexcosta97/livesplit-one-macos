The timer window shows your layout and nothing else. It has no title bar and no buttons. Everything else is in its right-click menu: see [The Menu](The-Menu).

<!-- screenshot: S1 timer-window.png -->
The timer window with a layout, running.

## Moving and resizing

Drag anywhere in the window to move it. Drag an edge or a corner to resize it. The layout stretches to fill the window, as it does in LiveSplit One.

## Always on Top

Right-click the timer and choose **Always on Top** to keep the window above other apps' windows, for example over a game in a window. Choose it again to turn it off. The app remembers it.

## Keyboard shortcuts

While the timer window is in front, these keys run the timer's commands:

| Key | Command |
|---|---|
| Space | **Start** or **Split** |
| ⌫ (Delete) | **Reset** |
| U | **Undo Split** |
| S | **Skip Split** |
| P | **Pause** or **Resume** |

**Undo All Pauses** has no key until you give it one. A key does nothing when its command is greyed out in the menu, and holding a key down runs its command once.

A letter works whichever key types it on your keyboard layout, with or without Caps Lock. While the timer window is in front, the menus show next to each command its first key that a menu can show: keys on the numeric keypad aren't shown in menus.

To change them, open **Settings…** (⌘,): see [Settings and Logs](Settings-and-Logs#the-settings-window). The keys work only while the timer window is in front, not while you're in a game. Keys that work everywhere are planned.

## Size and position

The first time, the window opens in the middle of the screen at 300 × 500 points, LiveSplit One's size for a new layout. After that it opens where you left it, at the size you left it.

When the layout gets taller or shorter, the window grows or shrinks with it and keeps its top-left corner where it is.

If the place the window was last isn't on a screen any more, or only a sliver of it is, for example after unplugging a display, it opens in the middle of the main screen instead. If the window is larger than the screen it opens on, it shrinks to fit. See [Troubleshooting](Troubleshooting#the-window-is-somewhere-i-cant-see).

While the timer isn't running, the app redraws the window only when something changes, so an idle timer uses almost no processor time.

## The display stays on during a run

While the timer is running, your Mac's display doesn't go to sleep, so the screen saver doesn't start and the Mac doesn't lock, even if you play with a controller and never touch the keyboard or mouse. It works as it does while a video plays. Once you pause, finish or reset, the display sleeps again after the time set in System Settings. You can still put the Mac to sleep or lock it yourself.

## What it shows at first

The first time, the window shows LiveSplit One's default layout and a run with one segment, **Time**. After you open splits or a layout, the app reopens them at launch: see [Splits and Layouts](Splits-and-Layouts#what-opens-at-launch).

The layout's own words, such as **Previous Segment**, are in your Mac's language when LiveSplit One has it, and in English otherwise.

## Notices

Short messages sometimes appear over the bottom of the timer, for 4 seconds each. They aren't part of the layout and are never saved. When several come at once, they appear one after another.

| Notice | What it means |
|---|---|
| **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** | The settings file was damaged, so the app started with the default settings and kept the old file. See [Troubleshooting](Troubleshooting#the-settings-were-reset). |
| **Couldn't read the settings, so the defaults are used and changes aren't saved.** | The settings file couldn't be read, nor set aside. The app won't save settings until it restarts, so the file isn't overwritten. See [Troubleshooting](Troubleshooting#changes-to-the-settings-arent-saved). |
| **Couldn't reopen "&lt;name&gt;": &lt;reason&gt;** | The splits or layout you had open last time couldn't be opened at launch, so the default layout or a new run is shown. See [Troubleshooting](Troubleshooting#a-file-didnt-reopen-at-launch). |
| **Couldn't open the layout "&lt;name&gt;" these splits use: &lt;reason&gt;** | The splits you opened name a layout that couldn't be opened, so the layout you had stays. See [Splits and Layouts](Splits-and-Layouts#layouts-that-splits-use). |
| **Connected to &lt;host&gt;** | The app is connected to a timer server. See [Connecting to a Server](Connecting-to-a-Server#what-the-timer-shows). |
| **Couldn't connect to &lt;host&gt;: &lt;reason&gt;** | Connecting to a server failed. See [Connecting to a Server](Connecting-to-a-Server#what-the-timer-shows). |
| **Lost connection to &lt;host&gt;, retrying…** | The connection to the server stopped, and the app is trying again. See [Connecting to a Server](Connecting-to-a-Server#when-the-connection-is-lost). |
