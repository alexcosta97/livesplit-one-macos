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
| LiveSplit One's Tauri build | Still the web UI inside a WebView. Pop Out does nothing: WKWebView returns `null` from `window.open` before Tauri's new-window handler runs. Connecting to the bridge failed, cause not established |
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
- Target: macOS 14 (Sonoma) or newer.

## 4. Architecture

```
┌──────────────────────────── Mac ────────────────────────────┐          ┌── gaming PC ──┐
│  App (Swift, AppKit)                                        │          │               │
│   TimerWindow ── draws ──► CALayer ◄── pixels ─┐            │          │ livesplit-asr │
│   ContextMenu · SplitsEditor · ConnectDialog   │            │          │ -bridge       │
│        │ timer actions          ServerClient ──┼────────────┼─ ws:// ──┤ (WebSocket    │
│        ▼                        (URLSession    │            │ commands │  server)      │
│  LiveSplitCore (Swift package)   WebSocketTask)│            │  ◄─►     │               │
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
- **LiveSplitCore** (Swift package, `LiveSplitCore/`). The Swift bindings
  generated by livesplit-core's `bind_gen`, plus a hand-written wrapper for the
  extra functions. Generated files are produced by the build, not edited.
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
├── LiveSplitCore/           Swift package: generated bindings + wrapper
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
  changed, so an idle timer uses next to no CPU.
- The renderer's size hint after a layout loads gives the window its natural
  aspect ratio, as in LiveSplit One.
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

Each addition gets Rust unit tests in `core/`.

## 6. Timer window

- **Borderless.** Dragging anywhere in the window moves it. The edges resize
  it freely; the renderer fits the layout to the window, as LiveSplit One does
  when its window is resized.
- **Size and position** are remembered per layout file in `app.toml`. A layout
  opened for the first time takes the renderer's size hint.
- **Always on Top** is a menu toggle, remembered between launches.
- **On launch** the app reopens the last splits and layout and the window
  position. If a file is missing or no longer loads, it uses livesplit-core's
  default layout or an empty run, and shows an overlay notice that names the
  file.
- **Overlay notices** are short messages drawn over the bottom of the timer
  for 4 seconds: connection status, a file that couldn't be reopened. They are
  not part of the layout and are never saved.
- **Dock and menu bar.** The app has a Dock icon and a standard menu bar with
  the same commands as the right-click menu, as macOS expects.
- **Keyboard shortcuts** for the Control commands work while the window has
  focus. Global hotkeys are backlog.

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
Open Log Folder
About LiveSplit One for macOS
Quit
```

- Items that can't be used are disabled, not hidden: Edit Splits while the
  timer is running, Undo Split with nothing to undo, and so on.
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
  reset attempt counts as a change, as in LiveSplit.
- **Reset with new best times:** a Reset after beating some best times asks
  whether to update them, with *Yes / No / Don't Reset*, as LiveSplit One
  does. A reset from the server follows the same rule: when its command says
  whether to save the attempt, the app doesn't ask; when it doesn't, the app
  asks, and the server gets its reply once the user answers (section 5.3).
- A file that fails to load shows an alert with livesplit-core's reason. The
  current splits and layout stay as they were.
- A failed save shows an alert, and the run stays marked unsaved.
- File dialogs go through a `FilePicker` protocol (section 14.2).

## 8. Connect to Server

### 8.1 Connecting

- **Connect to Server…** opens a sheet on the timer window with a URL field,
  prefilled with the last URL used, and Connect and Cancel buttons. A URL
  without a scheme gets `ws://`. A URL that isn't `ws://` or `wss://` is
  rejected in the sheet with a reason.
- The client is `URLSessionWebSocketTask`. It sets no `Origin` header unless
  the server needs one; #7 checks livesplit-asr-bridge's handshake against a
  native client before the rest of the client (#14) is built.
- `Info.plist` contains `NSLocalNetworkUsageDescription`, so macOS asks for
  local network access the first time the app connects to another machine.

### 8.2 Messages

- Each text message from the server goes to `handle_command` (section 5.3) on a
  serial background queue. Replies are sent back in the order the messages
  arrived, as LiveSplit One does.
- A binary message gets `{"Err":{"code":"InvalidCommand"}}`, as in LiveSplit
  One.
- Every event from the command sink, whatever started it, is encoded with
  `encode_event` and sent to the server while connected. That way the bridge's
  tracked timer state is always right, including for splits made locally.

### 8.3 Status and reconnection

| State | Menu item | Overlay notice |
|---|---|---|
| Not connected | Connect to Server… | none |
| Connecting | Disconnect from `<host>` | none |
| Connected | Disconnect from `<host>` | "Connected to `<host>`" |
| Couldn't connect, first attempt | Connect to Server… | "Couldn't connect to `<host>`: `<reason from macOS>`" |
| Lost connection, retrying | Disconnect from `<host>` | "Lost connection to `<host>`, retrying…" |

- **Automatic reconnection.** This differs from LiveSplit One. If a connection
  that was open closes without the user choosing Disconnect, the app retries
  after 1 s, then 2, 4, 8, 16 and 30 s, and every 30 s after that, until it
  reconnects or the user chooses Disconnect. A failed first attempt does not
  retry, since the URL may be wrong.
- After reconnecting the notice says "Connected to `<host>`" again.
- **Disconnect** closes the socket with a normal close code and stops any
  retries.
- The last URL is saved in `app.toml`. The app does not reconnect on launch;
  the user chooses Connect to Server.

## 9. Splits editor

- **Edit Splits…** opens a modal window with **OK** and **Cancel**, like the
  classic LiveSplit. It is disabled while the timer is running.
- It edits a copy of the run through livesplit-core's `RunEditor`. **OK**
  replaces the timer's run with the edited one and marks the splits unsaved.
  **Cancel**, Escape and closing the window discard the copy.
- **The window holds no state of its own.** Every edit goes to `RunEditor`,
  which parses and validates input, and the window then redraws from the
  editor's state. Invalid time input is rejected the way LiveSplit One rejects
  it: the cell shows the error and keeps focus.
- **Contents:**
  - game icon (click to choose an image, or remove it), game name, category,
    start offset and attempt count;
  - a segment table (`NSTableView`): icon, segment name, split time, segment
    time, best segment, and one column per custom comparison;
  - buttons: Insert Above, Insert Below, Remove Segment, Move Up, Move Down;
  - comparisons: Add Comparison, Rename Comparison, Remove Comparison;
  - a Real Time / Game Time switch for which times the table shows and edits;
  - **Other ▸** Clear History, Clear Times (each asks for confirmation).
- Out of scope for the first version: speedrun.com metadata (region,
  platform, variables), Clean Sum of Best, custom variables, and auto
  splitter settings.

## 10. Error handling

| Situation | Behaviour |
|---|---|
| Splits or layout fail to parse | Alert with livesplit-core's reason; the current splits and layout are unchanged |
| Last splits or layout missing at launch | Default layout or empty run, plus an overlay notice naming the file |
| A save fails | Alert with the reason; the splits stay marked unsaved |
| Can't connect | Overlay notice with macOS's reason; menu back to Connect to Server…; logged as an error |
| Connection lost | Overlay notice; automatic reconnection (section 8.3); logged |
| The server sends an invalid command, or one the timer rejects | The error reply goes back as in LiveSplit One; logged in the Connection category; not shown as an error |
| `app.toml` can't be read or parsed | Defaults are used, the broken file is kept as `app.toml.bad`, and an overlay notice says so |
| The log folder can't be written | The app still runs; messages go to the unified log only (section 12.3) |

## 11. Configuration and settings storage

All settings live in one file, in the macOS standard per-user configuration
folder, the same one livesplit-asr-bridge uses (`dirs::config_dir()`):

```
~/Library/Application Support/livesplit-one-macos/
  app.toml
```

`app.toml` holds:

- the last splits and layout paths, and the recent files lists (10 each);
- the window frame per layout path, and Always on Top;
- the last Connect to Server URL.

It is read at launch and written when one of these changes. It is TOML, as in
livesplit-asr-bridge, read and written with a Swift TOML library through
`Codable`.

The splits and layouts themselves stay wherever the user keeps them; the app
only stores their paths.

## 12. Logging

### 12.1 Categories

| Category | Contents |
|---|---|
| Errors | File load and save failures, connection failures, unexpected states |
| Connection | Connecting, connected, disconnected, retries, each command received and its reply, each event sent |
| Timer | Timer actions and their source (menu, keyboard, server), run and layout changes |
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
| **Integration** | Swift Testing with the real livesplit-core and an in-process **fake server** (a Network.framework WebSocket listener) | Modules together, no user flow: server commands move the timer and events reach the server in order; open, edit and save a run; reconnection; rendering of reference layouts compared with snapshots | Module and app APIs; checks events, messages, timer state, files and pixels |
| **E2E** | XCUITest | The whole app as a user uses it | **Only** user input to the window (clicks, right-clicks, typing, keys, resizing, files the user picks) and only what the user can observe (what the window shows, what the fake server receives, files on disk) |

### 14.2 E2E harness

- Launches the real app with a temporary config and log folder, set by launch
  arguments that only test builds accept.
- **File dialogs:** the app opens `NSOpenPanel` and `NSSavePanel` through a
  `FilePicker` protocol. E2E runs switch to a scripted picker that answers with
  a file or a cancel, as a user would. The types and starting folder the app
  asks for are checked by lower-level tests.
- The fake server from the integration tests runs in the test process, and the
  app connects to it on `127.0.0.1`.

### 14.3 E2E flows (one main-path test each)

- First launch with no settings: default layout, empty run.
- Open splits and a layout; relaunch reopens them at the same window position.
- Right-click → Control → Start/Split, Undo, Reset with the new-best-times
  prompt.
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
- **CI** on pull requests, on `macos-latest` runners because Xcode needs them:
  - `setup`: builds `core/` and the app once and saves the Cargo and Xcode
    caches;
  - `lint`: `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D
    warnings`, `swift format lint --strict`;
  - `test`: `cargo test --locked`, then the unit, headless UI and integration
    tests;
  - `e2e`: the XCUITest suite;
  - `build`: a release build of the universal `.app`, uploaded as an artifact;
  - `commitlint` and `pr-title`: Conventional Commits on the title and every
    commit.

  On merge to `main` CI only builds, to warm the caches. Tests are not
  repeated, since a pull request can't merge without them.
- **Renovate** weekly, as in livesplit-asr-bridge: crates that ship and the
  LiveSplit crates (grouped, labelled `livesplit`) are `fix(deps)`; Swift
  packages that ship are `fix(deps)`; GitHub Actions are `ci(deps)`; mise tools
  and development-only packages are `chore(deps)`.
- **Tools** (XcodeGen, git-cliff, shellcheck, actionlint) are pinned in
  `mise.toml` and used both locally and in CI. Rust comes from
  `rust-toolchain.toml`.
- **Releases** work exactly as in livesplit-asr-bridge: the version comes from
  the Conventional Commits with git-cliff, starting at `0.1.0`. Every merge
  that produces a version publishes a release candidate `vX.Y.Z-rc.N`. Approval
  in the `release` environment promotes it to a full release marked Latest.
  The Releases page is the changelog. The build is a universal (Apple Silicon
  and Intel) unsigned `.app` in a `.zip`.

## 16. Documentation

- **README:** what the app is (unofficial, LiveSplit One, macOS) in the first
  line, download from `/releases/latest`, opening an unsigned app (System
  Settings → Privacy & Security → Open Anyway), connecting to
  livesplit-asr-bridge, where settings and logs are, and building from source.
- **CONTRIBUTING:** as section 15.
- **Wiki** (backlog): setup, connecting, files, troubleshooting, and settings
  and log locations.

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

First version:

- #11 Timer window: borderless window, rendering, size hint, resizing, Always
  on Top, overlay notices.
- #12 Files: open and save splits, open layout, Save Layout As, recents,
  unsaved-changes and reset prompts, reopen on launch.
- #13 Right-click menu and menu bar, with keyboard shortcuts while focused.
- #14 Connect to Server: sheet, client, events to the server, status,
  automatic reconnection.
- #15 Splits editor.
- #16 `app.toml` settings storage.
- #17 Logging: categories, daily files, 7-day retention, size cap, Open Log
  Folder, unified log.
- #18 E2E harness and suite (section 14.2), filled in alongside #11–#17.

Later:

- #19 Global hotkeys, with a hotkey settings window (livesplit-core's hotkey
  system supports macOS, and needs Accessibility or Input Monitoring
  permission).
- #20 Layout editor.
- #21 Running auto splitters inside the app (livesplit-core's `auto-splitting`
  feature).
- #22 Code signing, notarisation and auto-update.
- #23 Metal renderer, if needed (section 5.2).
- #24 speedrun.com integration.
- #25 Wiki.

## 18. License

Dual licensed under MIT or Apache-2.0, at the user's option, as are
livesplit-core and livesplit-asr-bridge. The repository contains `LICENSE-MIT`
and `LICENSE-APACHE`, and `core/Cargo.toml` declares
`license = "MIT OR Apache-2.0"`.
