Each section starts with what you see. If yours isn't here, [report a bug](#reporting-a-bug).

## macOS says the app can't be opened

The app isn't notarised by Apple yet. [Installing](Installing#opening-the-app-for-the-first-time) shows how to open it with **Open Anyway**.

## The settings were reset

The app couldn't read its settings file, so it started with the defaults. The old file is kept as `app.toml.bad` in the same folder, and the day's log has an **ERROR** line saying why the file couldn't be read. [Settings and Logs](Settings-and-Logs#settings) says where both are.

## Reporting a bug

Open a [bug report](https://github.com/alexcosta97/livesplit-one-macos/issues/new?template=3-bug-report.yml) and attach the log file for the day it happened. [Settings and Logs](Settings-and-Logs#logs) says where the files are. Each time the app starts, the log records its version, so the file also says which version you were using.
