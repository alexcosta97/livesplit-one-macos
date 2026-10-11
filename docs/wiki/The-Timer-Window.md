The timer window shows your layout and nothing else. It has no title bar and no buttons.

<!-- screenshot: S1 timer-window.png -->
The timer window with a layout, running.

## Moving and resizing

Drag anywhere in the window to move it. Drag an edge or a corner to resize it. The layout stretches to fill the window, as it does in LiveSplit One.

## Size and position

The first time, the window opens in the middle of the screen at 300 × 500 points, LiveSplit One's size for a new layout. After that it opens where you left it, at the size you left it.

When the layout gets taller or shorter, the window grows or shrinks with it and keeps its top-left corner where it is.

If the place the window was last isn't on a screen any more, or only a sliver of it is, for example after unplugging a display, it opens in the middle of the main screen instead. If the window is larger than the screen it opens on, it shrinks to fit. See [Troubleshooting](Troubleshooting#the-window-is-somewhere-i-cant-see).

While the timer isn't running, the app redraws the window only when something changes, so an idle timer uses almost no processor time.

## What it shows at first

At first, the window shows LiveSplit One's default layout and a run with one segment, **Time**.

The layout's own words, such as **Previous Segment**, are in your Mac's language when LiveSplit One has it, and in English otherwise.

## Notices

Short messages sometimes appear over the bottom of the timer, for 4 seconds each. They aren't part of the layout and are never saved. When several come at once, they appear one after another.

| Notice | What it means |
|---|---|
| **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** | The settings file was damaged, so the app started with the default settings and kept the old file. See [Troubleshooting](Troubleshooting#the-settings-were-reset). |
| **Couldn't read the settings, so the defaults are used and changes aren't saved.** | The settings file couldn't be read, nor set aside. The app won't save settings until it restarts, so the file isn't overwritten. See [Troubleshooting](Troubleshooting#changes-to-the-settings-arent-saved). |
