# livesplit-one-macos

An unofficial native macOS version of **LiveSplit One**, the speedrun timer.
It is not made by the LiveSplit team, and it is a version of LiveSplit One,
not of the original Windows LiveSplit.

LiveSplit One for macOS is a Swift and AppKit app built on
[livesplit-core](https://github.com/LiveSplit/livesplit-core), the library
that powers LiveSplit One. It behaves like the classic LiveSplit: a single
window showing only the timer, with everything else in a right-click menu. It
reads and writes the same splits and layout files as LiveSplit One, and draws
layouts with livesplit-core's own renderer, so a layout looks the same as in
LiveSplit One.

It is made for two-PC setups, for example a gaming PC running the game and
[livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge),
and a Mac showing the timer.

> **Status: in early development.** There is no release yet. The design is in
> [the design spec](docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md),
> and planned work is tracked in the
> [issues](https://github.com/alexcosta97/livesplit-one-macos/issues).

## What it will do

- Show a borderless timer window that draws a LiveSplit layout exactly as
  LiveSplit One does.
- Open and save splits (`.lss`), and open layouts (`.lsl` from the original
  LiveSplit and `.ls1l` from LiveSplit One), with recent files and a prompt
  before losing unsaved changes.
- Offer a right-click menu modelled on the classic LiveSplit's.
- Connect to Server: connect to livesplit-asr-bridge, or any other server
  that speaks LiveSplit One's protocol, and reconnect on its own if the
  connection drops.
- Edit splits in a native splits editor.
- Keep settings and logs in the same places, with the same log rotation, as
  livesplit-asr-bridge.
- Run on Apple Silicon and Intel Macs.

## Requirements

- macOS 14 (Sonoma) or newer, on an Apple Silicon or Intel Mac.

## Download

Once the first version is released, get it from
[the latest release](https://github.com/alexcosta97/livesplit-one-macos/releases/latest).
It is a `.zip` containing the app; unzip it and move the app to your
Applications folder.

### Opening the app the first time

The app is not signed by Apple yet, so macOS blocks it the first time you
open it. To open it:

1. Open the app. macOS says it can't be opened; close that message.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about the app and click **Open Anyway**, then
   confirm.

After that, the app opens normally.

## Using it with livesplit-asr-bridge

1. Run [livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge)
   on the machine running the game, load your auto splitter, and copy an
   address from its Timer card.
2. In LiveSplit One for macOS, right-click the timer and choose
   **Connect to Server…**.
3. Paste the address and click **Connect**.
4. When macOS asks to allow the app to find devices on your local network,
   allow it.

The bridge's auto splitter then starts, splits and resets the timer. If the
connection drops, for example because the bridge or the gaming PC restarted,
the app reconnects on its own. Choose **Disconnect from …** in the same menu to
stop.

## Settings and logs

Settings are stored in one file:

```
~/Library/Application Support/livesplit-one-macos/app.toml
```

It holds the last splits and layout opened, the recent files, the window
position for each layout, Always on Top and the last server address. Your
splits and layouts stay wherever you keep them; the app only stores their
paths.

Logs are written to:

```
~/Library/Logs/livesplit-one-macos/
```

- There is one file per day, named `livesplit-one-macos-YYYY-MM-DD.log`.
- Files older than 7 days are deleted.
- Each day's file is limited to 50 MB. Past that, only errors are written.
- Right-click the timer and choose **Open Log Folder** to open the folder in
  Finder. Console.app also lists the files, under **Log Reports**.

These follow the same rules as livesplit-asr-bridge.

## Building from source

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up a development
environment, the commit and pull request conventions, and how releases work.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
