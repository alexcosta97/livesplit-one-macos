Each section starts with what you see. If yours isn't here, [report a bug](#reporting-a-bug).

## macOS says the app can't be opened

The app isn't notarised by Apple yet. [Installing](Installing#opening-the-app-for-the-first-time) shows how to open it with **Open Anyway**.

## The settings were reset

The timer showed **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** The app couldn't read its settings file, so it started with the defaults. The old file is kept as `app.toml.bad` in the same folder, and the day's log has an **ERROR** line saying why the file couldn't be read. [Settings and Logs](Settings-and-Logs#settings) says where both are.

## Changes to the settings aren't saved

The timer showed **Couldn't read the settings, so the defaults are used and changes aren't saved.** The app couldn't read its settings file, and couldn't move it aside either, usually because of the file's or the folder's permissions. So that your file isn't lost, the app doesn't save settings until it restarts.

Quit the app, then in Finder check that you can open `app.toml` in the folder [Settings and Logs](Settings-and-Logs#settings) names. Fix its permissions, or move it somewhere else, and open the app again.

## The window is somewhere I can't see

The window opens where it was last. If that place isn't on a screen any more, it opens in the middle of the main screen. If it's on a screen you can't see, quit the app, move `app.toml` out of its folder (see [Settings and Logs](Settings-and-Logs#settings)), and open the app again: the window opens in the middle of the screen with the default settings.

## Reporting a bug

Open a [bug report](https://github.com/alexcosta97/livesplit-one-macos/issues/new?template=3-bug-report.yml) and attach the log file for the day it happened. [Settings and Logs](Settings-and-Logs#logs) says where the files are. Each time the app starts, the log records its version, so the file also says which version you were using.
