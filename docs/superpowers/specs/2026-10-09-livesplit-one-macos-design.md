# livesplit-one-macos: design

Date: 2026-10-09
Status: draft for review

## 1. Summary

livesplit-one-macos is an unofficial, native macOS desktop version of
**LiveSplit One**, written in Swift with AppKit on top of
[livesplit-core](https://github.com/LiveSplit/livesplit-core), the library that
powers LiveSplit One. It behaves like the classic LiveSplit: a single window
showing only the timer, with everything else in a right-click menu that opens
native windows and dialogs.

It reads and writes the same splits and layout files as LiveSplit One and the
Linux [livesplit-one-gtk](https://github.com/hoXyy/livesplit-one-gtk), and
renders layouts with livesplit-core's own renderer, so a layout looks the same
in all of them.

Typical use: a two-PC setup where the game and
[livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge) run
on a gaming PC, and this app shows the timer on a Mac. The app connects to the
bridge over LiveSplit One's **Connect to Server** WebSocket protocol, and the
bridge's auto splitter drives the timer.

It will be published on GitHub for the speedrunning community.

### 1.1 Why a new app

These were tried or reviewed first (October 2026):

| Option | Why not |
|---|---|
| LiveSplit One in a browser | Not native; the browser is required |
| LiveSplit One's Tauri build | Still the web UI inside a WebView. Pop Out does nothing: WKWebView returns `null` from `window.open` before Tauri's new-window handler runs. Connecting to the bridge failed. The cause is most likely the home network, not the client: a native client also got no answer from the bridge's LAN address, but connected over the PC's Tailscale address (#7) |
| Splitter (Swift, Mac App Store) | Doesn't load LiveSplit layout files, and doesn't look or behave like LiveSplit |
| livesplit-one-druid | Native, but built on the unmaintained Druid toolkit, and has no WebSocket client, only a TCP listener on `127.0.0.1` |
| livesplit-one-gtk | Linux only (X11, evdev) |

## 2. Goals and non-goals

### Goals (first version)

- A borderless timer window that renders a LiveSplit layout exactly as
  LiveSplit One does.
- Open and save splits (`.lss`) and open layouts (`.lsl` from the original
  LiveSplit and `.ls1l` from LiveSplit One), with recent files and
  unsaved-changes prompts.
- A right-click menu modelled on the classic LiveSplit's.
- Connect to Server: a WebSocket client for livesplit-asr-bridge and any other
  server that speaks LiveSplit One's protocol, with automatic reconnection.
- A native splits editor.
- Settings and logs stored in the same places, with the same rotation, as
  livesplit-asr-bridge.
- Unsigned builds for Apple Silicon and Intel, released through GitHub.
- User documentation in the repository's GitHub wiki (section 16), enough
  for someone new to install the app and use every feature above. The app
  isn't made public without it.

### Non-goals (first version)

- Global hotkeys (backlog). Keyboard shortcuts work while the window has
  focus.
- A layout editor (backlog). Layouts are made elsewhere and opened here.
- Running auto splitters inside the app (backlog). livesplit-asr-bridge runs
  them.
- speedrun.com integration: leaderboards, run metadata, uploading (backlog).
- Code signing, notarisation and auto-update (backlog).
- iOS, iPadOS, or any platform other than macOS.

### Success criteria

- A user opens their existing splits and layout, and the window looks the same
  as in LiveSplit One with those files.
- A user connects to livesplit-asr-bridge on another machine, starts the game,
  and the timer starts, splits, pauses game time and resets exactly as it would
  in LiveSplit One in Chrome.
- If the bridge or the gaming PC restarts, the timer reconnects without being
  touched.
- When something goes wrong, the user is told what happened and where the log
  is.
- Someone who has never used the app gets from the download to a connected,
  splitting timer using only the wiki.

## 3. Naming and positioning

- Name: **livesplit-one-macos** (repository, config and log folder names).
- Display name: **LiveSplit One for macOS**. The menu bar name
  (`CFBundleName`, 15 characters at most) is **LiveSplit One**.
- Bundle identifier: `dev.alexcosta.livesplit-one-macos`.
- The README's first line, the About window and the GitHub description say the
  app is **unofficial** and not made by the LiveSplit team, and that it is a
  version of LiveSplit One, not of the original Windows LiveSplit.
- The app icon lives in `assets/brand/icons/` as `icon.icns`, referenced by
  `CFBundleIconFile`. It is not the official LiveSplit icon.
- Target: macOS 15 (Sequoia) or newer.

## 4. Architecture

```
┌──────────────────────────── Mac ────────────────────────────┐          ┌── gaming PC ──┐
│  App (Swift, AppKit)                                        │          │               │
│   TimerWindow ── draws ──► CALayer ◄── pixels ─┐            │          │ livesplit-asr │
│   ContextMenu · SplitsEditor · ConnectDialog   │            │          │ -bridge       │
│        │ timer actions          ServerClient ──┼────────────┼─ ws:// ──┤ (WebSocket    │
│        ▼                        (URLSession    │            │ commands │  server)      │
│  LiveSplitCore (static lib)      WebSocketTask)│            │  ◄─►     │               │
│        │                             │         │            │ events   └───────────────┘
│        ▼                             ▼         │            │
│  core (Rust staticlib): livesplit-core C API + extras ──────┘
│   SharedTimer · Layout · SoftwareRenderer · RunEditor ·     │
│   event-reporting command sink · server protocol            │
│  Config (app.toml) · Log (daily files)                      │
└─────────────────────────────────────────────────────────────┘
```

Each component has one responsibility:

- **core** (Rust, `core/`). A static library that links livesplit-core and its
  C API (`livesplit-core-capi`), and adds the few functions a native app needs
  that the C API only offers on the web (section 5.3). livesplit-core does all
  of the timing, comparisons, parsing, saving, run editing and rendering.
  Swift never reimplements timer rules.
- **LiveSplitCore** (Xcode static library target, `LiveSplitCore/`). The Swift
  bindings generated by livesplit-core's `bind_gen`, plus a hand-written
  wrapper for the extra functions, in one Swift module. Generated files are
  produced by the build, not edited. It is an Xcode target rather than a Swift
  package because Xcode builds packages before any build phase, and its build
  phase (section 4.2) must regenerate the bindings first.
- **App** (Swift, AppKit, `App/`): the timer window, menu, dialogs and splits
  editor. No storyboards; views are built in code.
- **ServerClient**: the WebSocket client (section 8).
- **Config**: reads and writes `app.toml` (section 11).
- **Log**: writes the daily log files (section 12).

livesplit-core is used from upstream (`LiveSplit/livesplit-core`), pinned to
an exact git revision, not a fork.

### 4.1 Repository layout

```
livesplit-one-macos/
├── core/                    Rust crate "lso-core" (staticlib)
├── LiveSplitCore/           static library target: generated bindings + wrapper
├── App/                     AppKit app sources, by feature
│   ├── TimerWindow/
│   ├── Menu/
│   ├── Documents/           opening and saving, recents, unsaved prompts
│   ├── Server/
│   ├── SplitsEditor/
│   ├── Config/
│   └── Log/
├── Tests/                   Unit, HeadlessUI, Integration, E2E
├── project.yml              XcodeGen project definition
├── scripts/build-core.sh    builds core and regenerates the bindings
├── mise.toml                pinned tools
├── rust-toolchain.toml
└── .github/                 workflows, issue forms, PR template
```

The Xcode project is generated from `project.yml` with XcodeGen and is not
committed, so pull requests never conflict on `project.pbxproj`.

### 4.2 Build

- `scripts/build-core.sh` runs `cargo build` for `core/` and regenerates the
  Swift bindings with `bind_gen`. It builds for the host architecture in
  development, and for both `aarch64-apple-darwin` and `x86_64-apple-darwin`,
  joined with `lipo`, for releases.
- An Xcode build phase runs the script before compiling Swift. Its inputs are
  `core/**`, `Cargo.lock` and `rust-toolchain.toml`, so Xcode skips it when
  nothing on the Rust side changed.
- The version is embedded at build time from the release pipeline (section
  15): `LSOVersion` in `Info.plist` holds the full version, such as
  `0.4.0-rc.2`, which the app shows, and `CFBundleShortVersionString` holds
  `0.4.0`, since bundle versions must be numbers. There are no version-bump
  commits.

## 5. Timer and rendering

### 5.1 Timer

- The app holds one livesplit-core `SharedTimer`. Commands from the menu,
  keyboard shortcuts and the bridge all go through the same command sink
  (section 5.3), so they behave the same whatever their source.
- The timer's lock lives in livesplit-core. Bridge commands run on a
  background queue and take the write lock. Drawing only takes the read lock,
  long enough to update the layout state.

### 5.2 Rendering

- On every display refresh (`CADisplayLink` for the window's screen), the app
  updates the layout state from the timer and renders it with livesplit-core's
  `SoftwareRenderer` into an RGBA pixel buffer at the window's backing scale
  (Retina aware). The buffer becomes a `CGImage` set as the view layer's
  contents.
- The renderer only draws again when the layout state changed or the size
  changed, so an idle timer uses next to no CPU. `core/` compares each frame's
  layout state, encoded as JSON, with the last frame's (section 5.3). While the
  timer is running, the app updates the layout state every frame; otherwise only
  after something changes it (`TimerContent.markChanged()`), when its phase
  changes (a split that ends the run, a pause, a reset), or every half second
  as a backstop, so a missed change shows within about 0.75 s. While the timer
  isn't running, the display link runs at 4 Hz, and returns to the display's
  rate as soon as something changes.
- A new layout starts at 300 × 500 points, LiveSplit One's default. When the
  layout's height changes (another layout opens, segments are added), the
  renderer gives a size hint, and the window takes that size, keeping its
  top-left corner, as LiveSplit One does.
- The layout's text, such as component names, is in macOS's first preferred
  language when livesplit-core has it, as LiveSplit One follows the browser's
  language.
- A Metal-based renderer is backlog, if profiling shows the software renderer
  costs too much.

### 5.3 Additions to the C API (`core/`)

livesplit-core's C API exposes `ServerProtocol` only when built for the web
(`target_family = "wasm"`). On native, `SharedTimer` already implements the
`CommandSink` and `TimerQuery` traits that the protocol needs, so `core/` adds:

- **An event-reporting command sink.** It wraps the `SharedTimer`, applies each
  command and reports the resulting `Event`, or the error, to Swift through a
  C callback. This matches LiveSplit One's own `LSOCommandSink`, which sends
  every event to the connected server.
- **Reset decisions.** When a reset doesn't say whether to keep the attempt's
  times and the attempt has new best times, the sink asks Swift through a
  second callback and waits for the answer, as LiveSplit One's sink waits for
  its dialog. Any reset that doesn't say whether to keep the attempt's times,
  new best times or not, first waits for commands already running to finish
  and be reported. From its start until its own result has been reported,
  other commands return `Busy`, including while it asks when it has to, as in
  LiveSplit One. Every report must therefore return promptly, without waiting
  on other commands. Server commands run on a background queue (section 8.2),
  so waiting never blocks the main thread.
- **`handle_command(json) -> json`**: runs one server protocol message against
  the sink with `futures::executor::block_on`, which completes at once for a
  local timer, and returns the reply to send back.
- **`encode_event(event) -> json`**: encodes an event as LiveSplit One does, to
  send to the server.
- **Rendering that skips unchanged frames.** `LsoRenderer_render` wraps
  livesplit-core's `BorrowedRenderer`. It compares the layout state, encoded
  as JSON, and the image's size with the last frame's, and draws only when
  one of them changed. It also returns the renderer's size hint, which the C
  API's `SoftwareRenderer_render` discards.

Each addition gets Rust unit tests in `core/`.

## 6. Timer window

- **Borderless.** Dragging anywhere in the window moves it. The edges resize
  it freely; the renderer fits the layout to the window, as LiveSplit One does
  when its window is resized. This holds where the layout is transparent too:
  WindowServer sends a click on a fully transparent pixel to the window below,
  so the view keeps a backing of 5/255 opacity (invisible; 4/255 is the least
  that works on macOS 27) for clicks to land on.
- **Size and position** are remembered per layout file in `app.toml`, and for
  the default layout, which has no file, in a key of its own (section 11). A
  layout opened for the first time keeps the window's size until the renderer's
  size hint changes it (section 5.2). A saved frame is used only if one screen
  shows at least 40 points of it in each direction (or all of it, in a
  direction where the window is smaller than that); otherwise the window is
  centred on the main screen instead, since it has no title bar to drag it back
  with. A saved frame larger than the screen it is most on is shrunk to fit
  that screen, keeping its top-left corner unless that would leave part of it
  off the screen. The screens are those at the moment the frame is used, also
  when a layout is opened: a frame saved for it that no screen shows enough of
  any more, as when a display was unplugged, puts the window in the middle of
  the main screen at the default size, and the layout's size hint then resizes
  it from its top-left corner as usual. A layout with no saved frame leaves the
  window where it is.
- **Always on Top** is a menu toggle, remembered between launches.
- **On launch** the app reopens the last splits and layout and the window
  position. If a file is missing or no longer loads, it uses livesplit-core's
  default layout or an empty run (LiveSplit One's new run: one segment named
  Time), and shows an overlay notice that names the file.
- **Overlay notices** are short messages drawn over the bottom of the timer
  for 4 seconds: connection status, a file that couldn't be reopened. They are
  not part of the layout and are never saved. When several come together, each
  shows for its 4 seconds in turn. One already shown or waiting isn't repeated.
- **Dock and menu bar.** The app has a Dock icon and a standard menu bar with
  the same commands as the right-click menu, as macOS expects.
- **Keyboard shortcuts** for the Control commands work while the timer window
  has focus. Global hotkeys are backlog. See section 7.2.

## 7. Right-click menu

Modelled on the classic LiveSplit's:

```
Edit Splits…
Open Splits  ▸  Open…  /  recent files (10)  /  Clear Menu
Save Splits            ⌘S
Save Splits As…        ⇧⌘S
Close Splits
─────────────
Control  ▸  Start/Split · Reset · Undo Split · Skip Split · Pause ·
            Undo All Pauses
Compare Against  ▸  Personal Best · Best Segments · Average Segments · … ✓
                    ─── Real Time ✓ · Game Time
─────────────
Open Layout  ▸  Open…  /  recent files (10)  /  Clear Menu
Save Layout As…
─────────────
Connect to Server…     (Disconnect from <host> while connected or retrying)
Always on Top
─────────────
Settings…              ⌘,
Open Log Folder
About LiveSplit One for macOS
Quit                   ⌘Q
```

- Items that can't be used are disabled, not hidden: Undo Split with nothing
  to undo, and so on. Edit Splits, Open Splits (and its recent files) and
  Close Splits are disabled while an attempt is in progress, running, paused
  or finished and not yet reset, since replacing the run would drop the
  attempt, and while the splits editor is open.
- **Recent files** are listed by file name, most recent first, with the full
  path as the tooltip. Two with the same name in different folders add the
  parent folder's name, such as `Splits.lss — Races`.
- **Start/Split** reads *Start* while the timer isn't running and *Split*
  otherwise. **Pause** reads *Resume* while the timer is paused. The Control
  items show their first shortcut that a menu can show (section 7.2) while the
  timer window is in front. While another window is in front, they show none,
  so no menu can run a shortcut typed there.
- **Commands** from the menus and shortcuts run through the same event-reporting
  command sink as server commands (section 5.1), on a background queue, since
  a reset can wait for a decision (section 5.3). Pause and Resume send `pause`
  and `resume`, never `togglePauseOrStart`, which would start a stopped timer.
- **The menu bar** has the same commands, in the menus macOS apps use:
  - *LiveSplit One*: About, Settings… (⌘,), Hide (⌘H), Hide Others (⌥⌘H),
    Show All, Quit (⌘Q).
  - *File*: Edit Splits…, Open Splits, Save Splits (⌘S), Save Splits As…
    (⇧⌘S), Close Splits, then Open Layout and Save Layout As…, as in the
    right-click menu.
  - *Edit*: Undo (⌘Z), Redo (⇧⌘Z), Cut (⌘X), Copy (⌘C), Paste (⌘V), Select
    All (⌘A), for the text fields of the splits editor and the Connect sheet.
    AppKit's text fields only get these keys from menu items.
  - *Control* and *Compare Against*, as in the right-click menu.
  - *Window*: Close (⌘W, for the Settings window; the timer window has no
    close button), Minimize (⌘M), Always on Top.
  - *Help*: Open Log Folder.
- **Compare Against** lists the run's comparisons, including custom ones, with
  a tick on the current one, and the timing method below a separator.
- **Save Layout As…** saves LiveSplit One's `.ls1l` format, the only layout
  format livesplit-core can write. For a layout opened from an `.lsl`, the
  save dialog suggests the same name with `.ls1l`, so the original file is
  never overwritten.
- **Edit Layout…** is added here when the layout editor is built (backlog).

### 7.1 Files and unsaved changes

- Splits open through livesplit-core's composite parser, so any format it
  reads opens (LiveSplit `.lss`, splits.io, Llanfair, WSplit and others). They
  are always saved as `.lss`. Saving a file that wasn't `.lss` asks for a new
  file name.
- **Unsaved splits:** opening other splits, Close Splits and Quit ask
  *Save / Don't Save / Cancel* when the run has unsaved changes. A finished or
  reset attempt counts as a change, as in LiveSplit. Quitting with an attempt
  in progress first resets it, as LiveSplit does when it closes, so the
  attempt is kept in the splits' history and asked about like any other
  change; that reset follows the rule below for new best times.
- **Linked layouts:** splits saved by LiveSplit can name a layout. Opening
  such splits from the menu opens that layout too, or the default layout when
  the link is to it. If the layout can't be opened, the current one stays and
  an overlay notice names the file. At launch the last layout is reopened
  instead, since it is the one that was showing. The app changes the link
  only when the user chooses one in the splits editor (section 9).
- **Reset with new best times:** what a Reset after beating some best times
  does is a setting, `reset_saves_best_times` (section 11), changed in the
  Settings window (section 7.3): *Ask*, *Update them* or *Keep the old ones*.
  While it is *Ask* (the default), the Reset asks whether to update them, with
  *Yes / No / Don't Reset*, as LiveSplit One does, and saves a *Yes* or *No*
  as the setting, so it asks only once. *Don't Reset* cancels the reset and
  isn't saved. A reset from the server follows the same rule: when its command
  says whether to save the attempt, the app doesn't ask; when it doesn't, the
  setting decides, and if it is *Ask* the server gets its reply once the user
  answers (section 5.3). Menu and keyboard commands that were waiting behind
  the question, such as a Space pressed just after Reset, are dropped and
  logged once it closes, so a stray key doesn't start a new attempt.
- A file that fails to load shows an alert. It gives macOS's reason when the
  file can't be read (missing, no permission), and otherwise says the file
  isn't splits, or a layout, that the app can read: livesplit-core's parsers
  don't say why a file didn't parse. The current splits and layout stay as
  they were.
- A failed save shows an alert, and the run stays marked unsaved.
- File dialogs go through a `FilePicker` protocol (section 14.2).

### 7.2 Keyboard shortcuts

- Each Control command has a list of shortcuts, any of which runs it while the
  timer window has focus. The defaults are single keys, as in terminal apps:

  | Command | Default |
  |---|---|
  | Start/Split | `Space` |
  | Reset | `Backspace` (⌫) |
  | Undo Split | `u` |
  | Skip Split | `s` |
  | Pause/Resume | `p` |
  | Undo All Pauses | none |

- A shortcut is a key with any of the modifiers `Shift`, `Control`, `Alt` (⌥)
  and `Meta` (⌘): `"u"`, `"Space"`, `"Numpad1"`, `"Control+Shift+Space"`. As
  in most Mac apps, a key is matched by the character it types with no
  modifiers on the current keyboard layout, not by where it is: `u` is
  whichever key types *u*, on QWERTY, AZERTY or Dvorak alike. Letters are
  written lowercase, and Caps Lock doesn't change them; Shift does, so
  `Shift+u` is a different shortcut from `u`. Keys that type nothing visible,
  or that are also on the numeric keypad, have names: `Space`, `Backspace`,
  `Delete`, `Enter`, `Tab`, `Escape`, `Up`, `Down`, `Left`, `Right`, `Home`,
  `End`, `PageUp`, `PageDown`, `F1` to `F20`, and `Numpad0` to `Numpad9`,
  `NumpadDecimal`, `NumpadAdd`, `NumpadSubtract`, `NumpadMultiply`,
  `NumpadDivide`, `NumpadEnter`, `NumpadEqual`, `NumpadClear`. So `1` and
  `Numpad1` are different shortcuts.
- Caps Lock, and the function and numeric-pad flags AppKit adds by itself,
  don't count as modifiers.
- A shortcut runs its command only if the menu item would be enabled. One the
  window doesn't use goes on to the menu bar, so ⌘Q and the rest still work.
- macOS keeps some combinations for itself, such as ⌃Space for the input
  source. The app never receives those, so they can't be recorded.

### 7.3 Settings window

Opened with Settings… (⌘,). One window, with two sections:

- **General:** *When a reset has new best times:* Ask / Update them / Keep the
  old ones (section 7.1).
- **Shortcuts:** each Control command with its shortcuts, shown as they look
  on the current keyboard. **+** records the next key press, Esc or leaving
  the window cancels recording, and × removes a shortcut. A shortcut that
  another command uses isn't added, and the row says which command has it.
  ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘, ⌘W, ⌘S and ⇧⌘S can't be recorded. **Restore Defaults** puts
  back section 7.2's defaults.

Every change is saved at once and shows in the menus.

## 8. Connect to Server

### 8.1 Connecting

- **Connect to Server…** opens a sheet on the timer window with a URL field,
  prefilled with the last URL used, and Connect and Cancel buttons. Connect is
  the default button and is disabled while the field is empty; Esc is Cancel.
  A URL without a scheme gets `ws://`. The sheet stays open and says why
  below the field when the URL can't be used: **Use a ws:// or wss:// address.**
  for another scheme, **Enter the server's address.** when it has no host.
  Connect saves the URL as typed, trimmed of spaces, before connecting.
- `<host>` in the menu, notices and log is the URL's host, with `:<port>` when
  the URL names a port, such as `192.168.1.20:9087`.
- The client is `URLSessionWebSocketTask`, and sends no `Origin` header:
  `URLSessionWebSocketTask` adds none, and livesplit-asr-bridge doesn't check
  it (it accepts with tungstenite's `accept_async`). A native client
  (`scripts/handshake-check.swift`) connected to the bridge on the gaming PC
  with no `Origin`, over the PC's Tailscale address, and answered its
  `getCurrentState` and `start` commands (#7). A server that needs an
  `Origin` is not supported in the first version. Over the PC's LAN
  address the same client got no answer at all, most likely because the
  home firewall drops the connection, so that is a network setting, not a
  client one.
- An attempt that gets no handshake within 10 s fails with **The server
  didn't answer within 10 seconds.**, so a dropped connection, as on that LAN
  address, reads differently from a refused one (macOS's reason, such as
  *Could not connect to the server.*).
- `Info.plist` sets `NSAllowsArbitraryLoads` under
  `NSAppTransportSecurity`. Without it, App Transport Security refused
  `ws://` to the gaming PC's Tailscale address (`100.x.x.x`) with "The
  resource could not be loaded because the App Transport Security policy
  requires the use of a secure connection", while `127.0.0.1` worked (#14).
  The user chooses the server, so the hosts can't be listed, and
  `NSAllowsLocalNetworking` would make macOS ignore `NSAllowsArbitraryLoads`
  while covering only local names.
- `Info.plist` contains `NSLocalNetworkUsageDescription`, so macOS asks for
  local network access the first time the app connects to another machine.
  Until access is allowed, URLSession fails with "The Internet connection
  appears to be offline" (`NSURLErrorNotConnectedToInternet`), as seen in
  #7. The app gives instead the reason **LiveSplit One for macOS needs local
  network access. Allow it in System Settings › Privacy & Security › Local
  Network.**

### 8.2 Messages

- Each text message from the server goes to `handle_command` (section 5.3) on
  the connection's own serial background queue, not the menus' (section 7), so
  a server command reaches the sink while a menu's reset waits for its
  question and gets `Busy`, as in LiveSplit One. Replies are sent back in the
  order the messages arrived, as LiveSplit One does. A reply to a message
  from a connection that has since closed is dropped, never sent on a newer
  one.
- A binary message gets `{"Err":{"code":"InvalidCommand"}}`, as in LiveSplit
  One.
- Every event from the command sink, whatever started it, is encoded with
  `encode_event` and sent to the server while connected. That way the bridge's
  tracked timer state is always right, including for splits made locally. An
  event caused by a server message is sent before that message's reply, as
  LiveSplit One does. Events while not connected are dropped, not queued.
- While connected the app sends a WebSocket ping every 10 s. No pong within
  10 s counts as a lost connection (section 8.3), so a server that vanished,
  such as a PC that went to sleep, is noticed.

### 8.3 Status and reconnection

| State | Menu item | Overlay notice |
|---|---|---|
| Not connected | Connect to Server… | none |
| Connecting | Disconnect from `<host>` | none |
| Connected | Disconnect from `<host>` | "Connected to `<host>`" |
| Couldn't connect, first attempt | Connect to Server… | "Couldn't connect to `<host>`: `<reason>`" |
| Lost connection, retrying | Disconnect from `<host>` | "Lost connection to `<host>`, retrying…" |

- **Automatic reconnection.** This differs from LiveSplit One. If a connection
  that was open closes without the user choosing Disconnect, the app retries
  after 1 s, then 2, 4, 8, 16 and 30 s, and every 30 s after that, until it
  reconnects or the user chooses Disconnect. A retry that fails shows no
  notice; it is logged. A failed first attempt does not retry, since the URL
  may be wrong.
- After reconnecting the notice says "Connected to `<host>`" again, and the
  next loss starts again from 1 s.
- **Disconnect** closes the socket with a normal close code and stops any
  retries. Quitting does the same.
- The last URL is saved in `app.toml`. The app does not reconnect on launch;
  the user chooses Connect to Server.
- The menu bar has the same item in the File menu, below Save Layout As….

## 9. Splits editor

- **Edit Splits…** opens a modal window titled **Edit Splits** with **OK**
  and **Cancel**, like the classic LiveSplit. It is disabled while an attempt
  is in progress (section 7).
- It edits a copy of the run through livesplit-core's `RunEditor`. **OK**
  replaces the timer's run with the edited one. The splits are then unsaved
  if any edit changed them: livesplit-core marks the run changed on each
  edit, so OK with no edits leaves them as they were. **Cancel**, Escape and
  closing the window discard the copy.
- **OK** is the default button: Return is OK, except while a table cell is
  being edited, where Return ends that cell's edit (checked as any other
  edit) and leaves the window open, so Return again is OK.
- While the window is open the timer's menus are unavailable, but a server
  can still start an attempt. If one started since the window opened,
  whether it is still in progress or was reset, OK is refused: replacing the
  run would drop the attempt, or the history, best times and attempt count
  it added, which the copy doesn't have. The app compares the timer's
  attempt count with the one it read when it took the copy, under the lock
  that replaces the run. OK says below the table **An attempt was started
  while the splits editor was open, so these changes can't be applied.
  Choose Cancel, then edit the splits again.**, and the window stays open
  with the edits.
- Quit waits while the window is open, since OK would replace the run after
  the unsaved-changes question was answered: it beeps and brings the window
  to the front, and does nothing else.
- **The window holds no state of its own.** Every edit goes to `RunEditor`,
  which parses and validates input, and the window then redraws from the
  editor's state. The one exception is the linked layout, which `RunEditor`
  takes but doesn't report: the window keeps the link it last set, starting
  from the run's.
- **Invalid input** is rejected the way LiveSplit One rejects it: a time,
  the start offset or the attempt count that doesn't parse turns red and
  keeps focus, and a line below the table says **Enter a time, such as
  1:23.45.** (or **Enter a whole number.** for the attempt count). An empty
  time clears it. Escape still cancels the whole window.
- **Contents:**
  - game icon (click to choose an image, or remove it), game name, category,
    start offset and attempt count;
  - **Layout:** which layout opens with these splits (section 7.1): **None**,
    the layout showing now (its file name, or **Default Layout**), and the
    one the splits link to, if it is another;
  - a segment table (`NSTableView`): icon, segment name, split time, segment
    time, best segment, and one column per custom comparison. Segment groups
    show as a header row above their segments, which are indented. A group's
    row has its icon and name, and no times; an empty name shows the name
    it takes from its last segment, greyed;
  - selection as in LiveSplit One: a click selects one row, ⌘-click adds or
    removes one, ⇧-click selects a range; clicking a group's row selects all
    its segments. Times are edited in the row that was clicked last;
  - buttons: Insert Above, Insert Below, Remove Segment, Move Up, Move Down,
    each enabled as `RunEditor` allows;
  - groups: **Create Group** makes the selected segments, which must be next
    to each other and in no group, a group; **Remove Group** turns the
    selected groups back into plain segments. A group's name and icon are
    edited in its row;
  - comparisons: **Add Comparison…**, **Rename Comparison ▸** and **Remove
    Comparison ▸**, the last two listing the custom comparisons. A name that
    is used already or starts with `[Race]` is refused, and the question
    stays open saying **That name is already used, or starts with [Race].**;
  - a Real Time / Game Time switch for which times the table shows and edits;
  - **Other ▸** Clear History, Clear Times (each asks for confirmation).
- Icons are read like splits files (section 7.1): a regular file, at most
  16 MB, in a format livesplit-core reads (PNG, JPEG, GIF, BMP, TIFF, WebP,
  ICO). One that can't be read shows an alert with the reason.
- Out of scope for the first version: speedrun.com metadata (region,
  platform, variables), Clean Sum of Best, custom variables, importing and
  generating comparisons, moving comparisons, and auto splitter settings.

## 10. Error handling

| Situation | Behaviour |
|---|---|
| Splits or layout fail to load | Alert with macOS's reason if the file can't be read, else that it isn't splits or a layout the app reads; the current splits and layout are unchanged |
| Last splits or layout missing at launch | Default layout or empty run, plus an overlay notice naming the file |
| A save fails | Alert with the reason; the splits stay marked unsaved |
| Can't connect | Overlay notice with macOS's reason; menu back to Connect to Server…; logged as an error |
| Connection lost | Overlay notice; automatic reconnection (section 8.3); logged |
| The server sends an invalid command, or one the timer rejects | The error reply goes back as in LiveSplit One; logged in the Connection category; not shown as an error |
| `app.toml` can't be read or parsed | Defaults are used, the broken file is kept as `app.toml.bad`, and an overlay notice says so |
| `app.toml` can't be read and can't be moved aside | Defaults are used, and nothing is saved until the app restarts, so the file is never overwritten; logged as an error and an overlay notice says so |
| The log folder can't be written | The app still runs; messages go to the unified log only (section 12.3) |
| Open Log Folder can't open the folder | Alert naming the folder, so it can be found by hand; logged as an error |

## 11. Configuration and settings storage

All settings live in one file, in the macOS standard per-user configuration
folder, the same one livesplit-asr-bridge uses (`dirs::config_dir()`):

```
~/Library/Application Support/livesplit-one-macos/
  app.toml
```

`app.toml` holds:

- the last splits and layout paths, and the recent files lists (10 each);
- the window frame per layout path, the default layout's window frame, and Always on Top;
- the last Connect to Server URL;
- what a reset with new best times does (section 7.1);
- the keyboard shortcuts that differ from the defaults (section 7.2).

It is read at launch and written when one of these changes, atomically, so a
crash mid-write leaves the old file whole. Launching never creates it. It is
TOML, as in livesplit-asr-bridge, read and written through `Codable` with
[swift-toml](https://github.com/mattt/swift-toml) (toml++ underneath, a Swift 6
package, maintained; TOMLKit was last released in January 2024). For
example:

```toml
# LiveSplit One for macOS settings. The app rewrites this file when a setting changes.

always_on_top = true
last_layout = "/Users/me/Layouts/Main.ls1l"
last_server_url = "ws://192.168.1.20:16834"
last_splits = "/Users/me/Splits/GTA San Andreas.lss"
recent_layouts = ["/Users/me/Layouts/Main.ls1l"]
recent_splits = ["/Users/me/Splits/GTA San Andreas.lss", "/Users/me/Splits/Any%.lss"]
reset_saves_best_times = true

[default_layout_window]
height = 500.0
width = 300.0
x = 120.0
y = 300.0

[shortcuts]
start_split = ["Space", "Numpad1"]
undo_all_pauses = ["Control+Shift+p"]

[[windows]]
height = 520.0
layout = "/Users/me/Layouts/Main.ls1l"
width = 300.0
x = 120.0
y = 640.0
```

Every key is optional: a missing key takes its default (nothing opened, no
recent files, Always on Top off) and an unknown key is ignored, so a file
from another version still reads. A key with the wrong type makes the file
unreadable. Recent lists are trimmed to 10 and repeats dropped. A window entry
missing a key makes the file unreadable too; one with a number that isn't
finite, a size that isn't positive, or a duplicate layout is dropped. The
`default_layout_window` table (with keys `x`, `y`, `width`, `height`) holds
the window's frame while the default layout is shown, which has no path. A
broken file replaces any older `app.toml.bad`.

`reset_saves_best_times` is absent while the app should ask (section 7.1).
The `[shortcuts]` table has one list per Control command (`start_split`,
`reset`, `undo_split`, `skip_split`, `pause`, `undo_all_pauses`), and holds
only the commands whose shortcuts differ from the defaults, so a later
version's new defaults reach anyone who never changed them. A command that
isn't listed has its defaults, and `[]` means no shortcut. An entry that
isn't a shortcut, that can't be recorded (section 7.3), or that an earlier
command in that order already has, is dropped and logged. A key in the
table that isn't a command is ignored and logged.

The splits and layouts themselves stay wherever the user keeps them; the app
only stores their paths.

## 12. Logging

### 12.1 Categories

| Category | Contents |
|---|---|
| Errors | File load and save failures, connection failures, unexpected states |
| Connection | Connecting, connected, disconnected, retries, each command received and its reply, each event sent. Server commands are logged here, not under Timer |
| Timer | Timer actions from the menu and keyboard and their source, run and layout changes |
| App | Launch, version, settings read and written, files opened and saved |

A game time set right after another is still applied and answered, but only
the first of such a run is logged, so a bridge sending the game time on every
tick doesn't fill the log. Any other command ends the run. This is the same
rule livesplit-asr-bridge uses.

### 12.2 On disk

Same rules as livesplit-asr-bridge:

- Every category is written to disk.
- One file per day, named `livesplit-one-macos-YYYY-MM-DD.log`, in
  `~/Library/Logs/livesplit-one-macos/`.
- Each line is the local time to the millisecond, the category's tag and the
  message, as in livesplit-asr-bridge:
  `19:31:01.254  CONNECTION  Connected to 192.168.1.20`. The tags are
  `ERROR`, `CONNECTION`, `TIMER` and `APP`. Line breaks in a message are
  written as `\n` (and a backslash as `\\`), so each entry is one line; tabs
  are `\t`, and any other control character, and U+2028 and U+2029, is
  `\u{1b}` with its code. The message is escaped once, in one place, whatever
  it holds, a file's path and macOS's reason for not reading it included.
- Files older than 7 days are deleted at launch and at each daily rotation.
- A per-day size cap of 50 MB. Past it, only errors are written, and one line
  records that the cap was reached.
- **Open Log Folder** in the right-click menu opens the folder in Finder.

`~/Library/Logs` is where Console.app lists apps' log files, under **Log
Reports**, so the files can be read there too. The location is documented in
the README, the bug report form and the wiki.

### 12.3 Unified log

Every line is also sent to `os.Logger` with subsystem
`dev.alexcosta.livesplit-one-macos` and the category above, so it shows in
Console.app's live stream alongside system messages, such as local network
permission decisions.

## 13. Security considerations

- The app connects only to the server the user enters. The connection is
  unencrypted unless the URL is `wss://`. Timer commands and events contain no
  sensitive data.
- A connected server can only drive the timer through the server protocol: it
  cannot read or write files.
- No App Sandbox in the first version: it would complicate opening files from
  anywhere and isn't needed for an unsigned build. Revisited with code signing
  (backlog).

## 14. Testing

### 14.1 The pyramid

As in livesplit-asr-bridge (its issue #67): many fast tests at the bottom,
fewer integration tests, and a small E2E suite at the top. A bug found at a
higher level gets a test at the lowest level that can catch it. Rough
proportions by count: 70–80 % unit and headless UI, 15–25 % integration,
under 10 % E2E.

| Kind | Tooling | Exercises | How it drives and checks |
|---|---|---|---|
| **Unit** | Swift Testing; `cargo test` for `core/` | One function or type: the C API additions, menu building and enabling, reconnect timing, URL validation, recents, `app.toml` reading and writing, log rotation and the size cap | Direct calls |
| **Headless UI** | Swift Testing, views and view controllers without a window | One view: the splits editor table and buttons, the Connect sheet, each alert's buttons, overlay notices | Actions on the view; checks its accessibility tree and what it asks the app to do |
| **Integration** | Swift Testing with the real livesplit-core and an in-process **fake server** (a Network.framework WebSocket listener) | Modules together, no user flow: server commands move the timer and events reach the server in order; open, edit and save a run; reconnection; rendering of reference layouts compared with reference images in `Tests/Integration/Snapshots/`, recorded with `TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1` and checked by eye | Module and app APIs; checks events, messages, timer state, files and pixels |
| **E2E** | XCUITest | The whole app as a user uses it | **Only** user input to the window (clicks, right-clicks, typing, keys, resizing, files the user picks) and only what the user can observe (what the window shows, what the fake server receives, files on disk) |

### 14.2 E2E harness

- Launches the real app with a temporary config and log folder, set by the
  launch arguments `-LSOConfigDirectory <path>` and `-LSOLogDirectory <path>`.
  Only Debug builds, which tests use, read them; Release builds don't contain
  them. When the app hosts the unit and headless UI tests, it uses a
  temporary folder too, so test runs never touch the developer's own files.
- **File dialogs:** the app opens `NSOpenPanel` and `NSSavePanel` through a
  `FilePicker` protocol. E2E runs switch to a scripted picker that answers with
  a file or a cancel, as a user would: the launch argument
  `-LSOPickedFiles '<JSON array>'` lists the answers in order, each an
  absolute path or `null` for a cancel. Only Debug builds read it. The files
  E2E tests open are in the E2E test bundle, which the app can read; the
  files they save go in the run's temporary folder. The types and starting folder the app
  asks for are checked by lower-level tests.
- The fake server from the integration tests runs in the test process, and the
  app connects to it on `127.0.0.1`.

### 14.3 E2E flows (one main-path test each)

- First launch with no settings: default layout, empty run.
- Open splits and a layout; relaunch reopens them at the same window position.
- Right-click → Control → Start/Split, Undo Split, Reset.
- Shortcuts: `Space` splits; a shortcut changed in the Settings window runs
  its command; ⌘Q quits.
- Reset with new best times: the prompt, and its answer saved (#12).
- Connect to Server with the fake server: its commands start and split the
  timer; a local split reaches it; it drops and the app reconnects.
- Edit Splits: rename a segment and change a time, then OK; and Cancel.
- Unsaved changes on Quit: Save writes the file.
- Compare Against and Real Time / Game Time change what the window shows.

### 14.4 Manual, before each full release

- The real livesplit-asr-bridge on the Linux gaming PC, with a real game and
  auto splitter.
- The maintainer's own layouts and splits, compared side by side with
  LiveSplit One in Chrome.

## 15. Repository conventions, CI and releases

These follow livesplit-asr-bridge (its spec sections 13 and 14, and its
`CONTRIBUTING.md`), adapted only where macOS requires it:

- `AGENTS.md` says where to find things, and `CLAUDE.md` contains
  `@AGENTS.md`. Rules for agents live in the repository, never only in an
  agent's memory. Git worktrees go beside the repository, for example
  `../livesplit-one-macos-wt/<name>`.
- `CONTRIBUTING.md`: development setup, Conventional Commits, signed commits,
  `<type>/<short-description>` branches, pull requests and how releases work.
- Issue forms for Task, Feature request and Bug report (the bug form names the
  log folder); blank issues disabled. Every pull request links an issue,
  except Renovate's. Labels match livesplit-asr-bridge's.
- A pull request template: linked issue, what changed and why, how it was
  tested, checklist.
- **`main` rulesets:** changes only through pull requests, the required checks
  below, all conversations resolved, signed commits, squash merging only; and a
  second ruleset letting only maintainers merge.
- **Release settings:** the `release` environment deploys only from `main`,
  with the maintainer as required reviewer. A tag ruleset, "release tags",
  stops `v*` tags being moved or deleted. Creating them isn't restricted:
  GitHub doesn't let the GitHub Actions app bypass a ruleset in a personal
  repository, so restricting creation would block the release workflow.
- **CI** on pull requests, on `xcode-27` runners because Xcode needs them:
  - `setup`: builds `core/` and the app with its tests once, hands the test
    build to `test` and `e2e`, and saves the Cargo cache (Xcode's DerivedData
    isn't cached: a fresh checkout invalidates it);
  - `lint`: `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D
    warnings`, `swift format lint --strict`, `actionlint` (which also runs
    shellcheck on the workflows' scripts), `shellcheck` on `scripts/` and the
    release script tests;
  - `test`: `cargo test --locked`, then the unit, headless UI and integration
    tests;
  - `e2e`: the XCUITest suite;
  - `build`: a release build of the universal `.app`, uploaded as an artifact;
  - `commitlint` and `pr-title`: Conventional Commits on the title and every
    commit.

  On merge to `main` CI only runs `setup`, to save the Cargo cache that pull
  requests restore (a pull request can read its base branch's caches, not
  other pull requests'). Tests are not repeated, since a pull request can't
  merge without them.
- **Renovate** weekly, as in livesplit-asr-bridge: crates that ship and the
  LiveSplit crates (grouped, labelled `livesplit`) are `fix(deps)`; Swift
  packages that ship are `fix(deps)`; GitHub Actions are `ci(deps)`; mise tools
  and development-only packages, including the npm packages for commitlint,
  are `chore(deps)`.
- **GitHub Actions are pinned to a full commit SHA**, with the exact version
  as a comment (`uses: actions/checkout@<sha> # v7.0.1`), every action
  including GitHub's own. A tag can be moved to different code, and the
  release jobs hold a token that can create tags and releases; a SHA can't
  be moved. Renovate keeps the pins up to date (`helpers:pinGitHubActionDigests`).
  The jobs that publish releases (`contents: write`) also run no third-party
  action: the release notes are written in the read-only `version` job and
  passed on as an artifact. This departs from livesplit-asr-bridge, which
  pins actions by tag.
- **Tools** (XcodeGen, git-cliff, shellcheck, actionlint, Node) are pinned in
  `mise.toml` and used both locally and in CI. commitlint is pinned in
  `package.json` and installed with `npm ci`, so the local check and CI's
  `commitlint` check run the same version. Rust comes from
  `rust-toolchain.toml`.
- **Releases** work as in livesplit-asr-bridge, except for strict rc tag
  matching, idempotent and draft-safe publish steps, the release script tests
  in the required `lint` job, and one universal artifact. The version comes
  from the Conventional Commits with git-cliff, starting at `0.1.0`. Every merge
  that produces a version publishes a release candidate `vX.Y.Z-rc.N`. Approval
  in the `release` environment promotes it to a full release marked Latest.
  The Releases page is the changelog. The build is a universal (Apple Silicon
  and Intel) ad-hoc signed, not notarised `.app` in a `.zip`. Only one Release
  run is live at a time (a newer merge cancels the older run, even one already
  approved), and an older run must never be re-run.

## 16. Documentation

These follow livesplit-asr-bridge (its spec section 15), adapted to this app.

- **README:** what the app is (unofficial, LiveSplit One, macOS) in the first
  line, requirements, download from `/releases/latest`, a quick start of a
  few steps, and links to the wiki. Details (opening an app that isn't
  notarised, connecting, where settings and logs are) live only in the wiki,
  so each fact is written once. Building from source stays in
  `CONTRIBUTING.md`.
- **CONTRIBUTING:** as section 15.
- **Wiki:** the user documentation, in the repository's GitHub wiki
  (sections 16.1 to 16.4). It is part of the first version (section 2): the
  app isn't made public until someone new can learn to use it from the wiki.

### 16.1 Wiki source and publishing

- The wiki's pages and images are written in `docs/wiki/` in this repository
  and changed through pull requests like any other change. The wiki is never
  edited directly, and wiki editing is restricted to collaborators.
- `scripts/wiki/check.sh` checks the pages on pull requests, in the `lint`
  job: every link to another page names a page that exists, every image
  exists, and every page is in the sidebar.
- `.github/workflows/wiki.yml` publishes them. On every push to `main` that
  changes `docs/wiki/`, and on manual dispatch, it checks out the wiki
  repository (`livesplit-one-macos.wiki`) with `GITHUB_TOKEN`, mirrors
  `docs/wiki/` into it (deleting pages that no longer exist), and commits as
  `github-actions[bot]` with the message "Sync from <short sha>". Nothing is
  pushed when nothing changed.
- GitHub creates the wiki repository only once its first page exists, so the
  first page is created by hand once, and the first sync replaces it.
- File names follow the wiki's conventions: `Home.md`, `_Sidebar.md`,
  `_Footer.md`, and one file per page with hyphens for spaces
  (`Getting-Started.md` is the page "Getting Started"). Links between pages
  use page names (`[Troubleshooting](Troubleshooting)`), and images are in
  `docs/wiki/images/`.

### 16.2 Pages

In sidebar order:

| Page | Kind | Contents | Written by |
|---|---|---|---|
| Home | Landing | What the app is (unofficial, a version of LiveSplit One), a diagram of the two-PC setup, where to start, links to every page | #25 |
| Installing | Task | Downloading, moving the app to Applications, opening an app that isn't notarised (Open Anyway), full releases and release candidates, updating by hand (no auto-update), uninstalling, including the settings and log folders | #25 |
| Getting Started | Tutorial | First launch through the first split: open splits and a layout, start and split with the keyboard, reset, save, then connect to livesplit-asr-bridge | #12, the first issue after which the whole tutorial works; #14 adds connecting |
| The Timer Window | Reference | Moving and resizing, Always on Top, the window remembered per layout, overlay notices and what each one means, the keyboard shortcuts and how to change them | #11, #13 |
| The Menu | Reference | Every item in the right-click menu and the menu bar (section 7), when each is disabled, Compare Against and the timing method | #13 |
| Splits and Layouts | Task | Opening splits in any format livesplit-core reads, opening `.lsl` and `.ls1l` layouts, recent files, saving, Save Layout As and why it writes `.ls1l`, unsaved changes, reset with new best times, what reopens at launch | #12 |
| Editing Splits | Task | The splits editor (section 9): game details, segments, times, comparisons, Real Time and Game Time, Clear History and Clear Times, OK and Cancel | #15 |
| Connecting to a Server | Task | Connecting to livesplit-asr-bridge, which address to use, local network access and where to allow it, the status notices, automatic reconnection, Disconnect, servers other than the bridge | #14 |
| Settings and Logs | Reference | `app.toml` and what it holds, `app.toml.bad`, the log folder, the categories, retention and the size cap, Open Log Folder, Console.app | #25, from what #16 and #17 built; #13 adds Open Log Folder and the Settings window (section 7.3) |
| Troubleshooting | Task | By symptom (what you see, why, what to do), ending with how to report a bug with the version and the day's log file | #25 starts it; each issue adds what it finds; #41 completes it |
| Upcoming Changes | Staging | Section 16.3 | #25 |

- Button, menu item and notice names are written as the app shows them, in
  bold. Each one is checked against `App/` before it is written.
- Each fact lives on one page; other pages link to it.
- The app is always named **LiveSplit One for macOS** in the pages;
  `livesplit-one-macos` only for files and folders. The voice is plain and
  direct: short sentences, the words the app shows, no marketing
  superlatives.

### 16.3 Upcoming changes

The wiki describes the latest full release, the one `/releases/latest` points
to. Until the first full release exists, the pages describe `main` and
Upcoming Changes is not used.

- After the first full release, a pull request that changes what users see
  adds its documentation to the Upcoming Changes page, under a heading naming
  the page it belongs on, instead of changing that page. Fixes to the
  documentation of released behaviour change the page directly.
- When a full release is promoted (section 15), the release job opens an
  issue "Move upcoming documentation into the wiki for vX.Y.Z" if the
  Upcoming Changes page has any entries. Its pull request moves each entry
  into its page and empties Upcoming Changes.
- With no entries, the page says the documentation matches the latest
  release.

### 16.4 Screenshots

- PNG, of the window or sheet only: no desktop, wallpaper or shadow.
  Captured at 2× and shown with `<img width=…>` at their logical size.
- Every shot uses the same splits and layout, from one app version.
- Named `<subject>.png` after what they show, so a change to a screen shows
  which shots to retake.
- A pull request that changes a screen that is in a screenshot says which
  screenshots need retaking. Until a screenshot exists, its page describes
  the screen in text and marks the place with
  `<!-- screenshot: <ID> <file> -->`.

| ID | File | Shows |
|---|---|---|
| S1 | `timer-window.png` | The timer window, running, with a layout |
| S2 | `right-click-menu.png` | The right-click menu, with Control open |
| S3 | `connect-sheet.png` | The Connect to Server sheet |
| S4 | `overlay-notice.png` | The "Connected to `<host>`" notice, crop |
| S5 | `splits-editor.png` | The splits editor with a custom comparison |
| S6 | `unsaved-changes.png` | The Save / Don't Save / Cancel alert |
| S7 | `reset-new-best.png` | The reset with new best times alert |
| S8 | `settings-window.png` | The Settings window, with a command that has two shortcuts |
| T1 | `macos-open-anyway.png` | System Settings, Privacy & Security, Open Anyway |
| T2 | `macos-local-network-prompt.png` | macOS asking to allow local network access |
| T3 | `macos-local-network-settings.png` | System Settings, Privacy & Security, Local Network, with the app allowed |

## 17. Backlog

Tracked as GitHub issues, created in this order.

Foundations:

- #2 Contributor docs: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `README.md`, issue forms, PR template, licenses, `mise.toml`.
- #3 Repository settings and the `main` rulesets (section 15).
- #4 The implementation plan for the foundations.
- #5 Xcode project scaffold: XcodeGen project with an empty AppKit app,
  `rust-toolchain.toml`, version embedded at build time.
- #6 `core/` crate and the LiveSplitCore Swift package: build script, generated
  bindings, the C API additions (section 5.3) with unit tests.
- #7 Check livesplit-asr-bridge's handshake with a native client: a test
  `URLSessionWebSocketTask` connects to the real bridge from the Mac and runs a
  command, and the `Origin` behaviour is settled. Done before #14.
- #8 CI checks (section 15), added as required checks in the `main` ruleset.
- #9 Release pipeline.
- #10 Renovate.

First version, in the GitHub milestone **First version**, in the order
they are done. Each has its own plan in `docs/superpowers/plans/`, written
when it is next, against the code that exists by then (#40 plans the first
three):

- #40 Plan the first version: user documentation in the first version, this
  order, and the plans for #17, #16 and #25.
- #17 Logging: categories, daily files, 7-day retention, size cap, Open Log
  Folder, unified log. First, because every later issue logs.
- #16 `app.toml` settings storage. Logs its own failures, so after #17.
- #25 Wiki: `docs/wiki/`, its check and publishing (section 16.1), the
  Upcoming Changes issue, and the pages for what exists by then (Home,
  Installing, Settings and Logs, Troubleshooting, Upcoming Changes), so each
  issue after it documents itself in its own page (section 16.2).
- #11 Timer window: borderless window, rendering, size hint, resizing, Always
  on Top, overlay notices.
- #13 Right-click menu and menu bar, with keyboard shortcuts while focused
  (customisable, section 7.2) and the Settings window (section 7.3). The
  Files, Connect and Edit Splits items are added by their issues.
- #12 Files: open and save splits, open layout, Save Layout As, recents,
  unsaved-changes and reset prompts (the reset prompt saves its answer,
  section 7.1), linked layouts, reopen on launch. Planned in #58.
- #14 Connect to Server: sheet, client, events to the server, status,
  automatic reconnection. Planned in #63.
- #15 Splits editor. Planned in #72.
- #18 E2E harness and suite (section 14.2), filled in alongside #11–#17:
  each issue adds its own flows from section 14.3, and #18 closes when they
  all pass.
- #48 Third-party licence notices: the release `.app` carries the notices
  of every third-party component it links (livesplit-core and its crates,
  swift-toml, toml++), generated or checked in CI. Before the first full
  release, since those licences require their notices to go with copies.
- #41 Complete the wiki for the first release: screenshots (section 16.4),
  a whole-wiki pass, Troubleshooting.

Later:

- Opening files by dropping them on the timer window, and from Finder
  (*Open With*, double-click), with document types in the app's
  `Info.plist`. The first version opens files from its menus only (#58).

- #19 Global hotkeys, set in the Settings window (section 7.3).
  livesplit-core's hotkey system supports macOS, and needs Accessibility or
  Input Monitoring permission. It names keys by their position, so the
  shortcuts' characters (section 7.2) are turned into key positions with the
  current keyboard layout.
- #20 Layout editor.
- #21 Running auto splitters inside the app (livesplit-core's `auto-splitting`
  feature).
- #22 Code signing, notarisation and auto-update.
- #23 Metal renderer, if needed (section 5.2).
- #24 speedrun.com integration.

## 18. License

Dual licensed under MIT or Apache-2.0, at the user's option, as are
livesplit-core and livesplit-asr-bridge. The repository contains `LICENSE-MIT`
and `LICENSE-APACHE`, and `core/Cargo.toml` declares
`license = "MIT OR Apache-2.0"`.
