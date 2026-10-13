Each section starts with what you see. If yours isn't here, [report a bug](#reporting-a-bug).

## macOS says the app can't be opened

The app isn't notarised by Apple yet. [Installing](Installing#opening-the-app-for-the-first-time) shows how to open it with **Open Anyway**.

## The settings were reset

The timer showed **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** The app couldn't read its settings file, so it started with the defaults. The old file is kept as `app.toml.bad` in the same folder, and the day's log has an **ERROR** line saying why the file couldn't be read. [Settings and Logs](Settings-and-Logs#settings) says where both are.

## Changes to the settings aren't saved

The timer showed **Couldn't read the settings, so the defaults are used and changes aren't saved.** The app couldn't read its settings file, and couldn't move it aside either, usually because of the file's or the folder's permissions. So that your file isn't lost, the app doesn't save settings until it restarts.

Quit the app, then in Finder check that you can open `app.toml` in the folder [Settings and Logs](Settings-and-Logs#settings) names. Fix its permissions, or move it somewhere else, and open the app again.

## A file didn't reopen at launch

The timer showed **Couldn't reopen "&lt;name&gt;": &lt;reason&gt;**. The app tried to open the splits or layout you had open last time, and couldn't, so it shows the default layout or a new run. The reason says why: macOS's reason when it couldn't read the file, such as a drive that isn't connected, or **it isn't splits this app can read** or **it isn't a layout this app can read** when the file is there but isn't in a format LiveSplit One reads.

The app keeps the file's path, so once the file is back, for example when the drive is connected, quit the app and open it again, or open the file from **File**. If you open other splits or a layout meanwhile, the app remembers those instead.

## A file won't open

An alert says **"&lt;name&gt;" isn't splits LiveSplit One for macOS can read.** or **"&lt;name&gt;" isn't a layout LiveSplit One for macOS can read.** The file isn't in a format LiveSplit One reads, or it's damaged, or it is empty. Your current splits and layout stay as they were. Check that you chose the right file: splits open from **Open Splits**, and layouts, which are `.lsl` or `.ls1l` files, from **Open Layout**. The day's log has a line saying which file it was (see [Settings and Logs](Settings-and-Logs#logs)). [Splits and Layouts](Splits-and-Layouts#when-a-file-doesnt-open) lists the other alerts.

## Open Splits is greyed out

An attempt is running, paused, or finished and not reset yet. Reset it, then open the splits. See [Splits and Layouts](Splits-and-Layouts#why-open-splits-is-greyed-out).

## The window is somewhere I can't see

The window opens where it was last. If that place isn't on a screen any more, or only a sliver of it is, it opens in the middle of the main screen. If the window is larger than the screen, it shrinks to fit. If it's on a screen you can't see, quit the app, move `app.toml` out of its folder (see [Settings and Logs](Settings-and-Logs#settings)), and open the app again: the window opens in the middle of the screen with the default settings.

## A keyboard shortcut does nothing

- The keys work only while the timer window is in front. Click the timer, then try again.
- A key does nothing while its command is greyed out in the right-click menu, for example **Split** after the run ended.
- If you changed a key, check it in **Settings…**. If you edited `app.toml` by hand, the app ignores a key it can't read and notes it in the day's log (see [Settings and Logs](Settings-and-Logs#logs)).

## The app can't connect to the server

The timer showed **Couldn't connect to &lt;host&gt;: &lt;reason&gt;**. The reason says what went wrong:

- **LiveSplit One for macOS needs local network access. Allow it in System Settings › Privacy & Security › Local Network.** macOS is blocking the connection. Turn on **LiveSplit One for macOS** in that list, then connect again.
- **The server didn't answer within 10 seconds.** Nothing answered at that address. Check that the server is running and that the address and port are right. If they are and it's a local address, the gaming PC's firewall is probably dropping the connection: allow the server's port through it, or connect through a VPN such as Tailscale, using the address the VPN gives the PC. See [Connecting to a Server](Connecting-to-a-Server#which-address-to-use).
- macOS's own reason, such as **Could not connect to the server.** The computer answered but nothing is listening on that port: the server isn't running, or the port is wrong.

The day's log has the same line, under **ERROR** (see [Settings and Logs](Settings-and-Logs#logs)).

## The connection keeps being lost

The timer showed **Lost connection to &lt;host&gt;, retrying…**. The server stopped answering: it was closed, the gaming PC went to sleep, or the network dropped. The app tries again by itself and shows **Connected to &lt;host&gt;** once the server is back. If it never comes back, check the server and the gaming PC's sleep settings. The log's **CONNECTION** lines give each reason, such as **The server stopped answering.** when the PC went to sleep. Choose **Disconnect from &lt;host&gt;** to stop retrying.

## Reporting a bug

Open a [bug report](https://github.com/alexcosta97/livesplit-one-macos/issues/new?template=3-bug-report.yml) and attach the log file for the day it happened. [Settings and Logs](Settings-and-Logs#logs) says where the files are. Each time the app starts, the log records its version, so the file also says which version you were using.
