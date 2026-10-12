# Connect to Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect to a LiveSplit One server such as livesplit-asr-bridge: the Connect sheet, server commands through the event-reporting sink, every event sent to the server, the status in the menu and the overlay notices, and automatic reconnection (spec §8) (issue #14).

**Architecture:** `ServerURL` (`App/Server/`) turns what the user typed into a `ws://` or `wss://` URL and the `<host>` the app shows. `WebSocket` is the one way the app talks to a server: `URLSessionWebSocket` wraps `URLSessionWebSocketTask` with the 10 s handshake timeout and the ping, and unit tests use a fake. `ServerClient` (main actor) owns the connection state (`ConnectionStatus`), the retry timing (`ReconnectDelays`), the notices and the log; it runs each server message on its own serial queue straight into the app's one `EventSink`, and sends every event the sink reports while connected. `CommandRunner` shares its sink and passes its events on. `ConnectSheet` is the sheet; `TimerMenus` adds **Connect to Server…** / **Disconnect from `<host>`** to both menus.

**Tech Stack:** Swift 6, AppKit (`NSWindow` sheet, `NSTextField`, `NSMenu`), Foundation's `URLSessionWebSocketTask`, Network.framework (`NWListener`, `NWProtocolWebSocket`) for the fake server, livesplit-core through `EventSink` (`handleCommand`, `encodeEvent`), Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md`, sections 5.1, 5.3, 7, 8 (rewritten by this plan's pull request), 10, 12.1, 13, 14 and 16.2. Issue: #14, with its comments (#7's handshake findings, logging from #45, settings from #49, notices from #53, `CommandRunner` from #56).

**Branch and worktree:** `feat/connect-to-server`, at `../livesplit-one-macos-wt/connect-to-server`, from `main` once #12 (Files) is merged. This plan builds on #12's code: the File menu, the reset question in `CommandRunner`, `FilePicker`'s launch-argument pattern. If something #12 built differs from what this plan says, follow the code and say so in the pull request. **PR title:** `feat: connect to a LiveSplit One server`. **PR body:** `Closes #14`, using the pull request template. One pull request for the whole plan; each task is one commit.

## Before you start

- Read `CONTRIBUTING.md`, the spec sections above and every comment on #14. Run the checks in `CONTRIBUTING.md` step 4 on `main` once.
- Read `App/AppDelegate.swift`, `App/Menu/CommandRunner.swift`, `App/Menu/TimerMenus.swift`, `App/TimerWindow/TimerWindowController.swift`, `App/TimerWindow/NoticeQueue.swift`, `App/Log/Log.swift`, `App/Log/GameTimeLogFilter.swift`, `App/Config/Settings.swift`, `App/Config/SettingsStore.swift`, `LiveSplitCore/Wrapper/EventSink.swift`, `scripts/handshake-check.swift`, `Tests/Integration/EventSinkTests.swift`, `Tests/Unit/CommandRunnerTests.swift`, `Tests/E2E/E2EApp.swift` and `Tests/E2E/MenuTests.swift`.
- Shell setup on the maintainer's Mac: `export PATH="$(brew --prefix rustup)/bin:$HOME/.cargo/bin:$PATH"`, then `mise install`.
- After adding Swift files or changing `project.yml`, run `xcodegen generate`.
- Run one suite with `xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:<Target>/<SuiteName>`.

## Global Constraints

- **One sink.** Every command, from any source, goes through the `EventSink` that `CommandRunner` made (spec §5.1). Swift never reimplements timer rules.
- **Two queues.** Server messages run on `ServerClient`'s serial queue (`dev.alexcosta.livesplit-one-macos.server`), never `CommandRunner`'s. So while a menu reset waits for its question the server gets `Busy` from the sink, as in LiveSplit One, and a server reset that asks blocks only the server queue (spec §8.2). Neither queue is the main thread. The main thread never waits on either queue.
- **`EventSink`'s callback rules hold.** `report` runs on the command's thread and returns at once: it may call `WebSocket.send` (which only queues the frame) and `Log.record`, nothing that waits, and never the sink.
- **Ordering on the wire:** an event caused by a server message is sent before that message's reply; replies go in the order messages arrived. Both follow from `send` being called in that order on one task.
- **Stale work is dropped.** Each connection attempt has a number (`generation`). A reply, event, open, close or failure from an older generation does nothing.
- **Texts, exactly** (spec §8):
  - Menu: **Connect to Server…**; **Disconnect from `<host>`** while connecting, connected or retrying.
  - Sheet: title **Connect to Server**, a label **Server address:**, placeholder `ws://192.168.1.20:9087`, buttons **Connect** and **Cancel**, errors **Use a ws:// or wss:// address.** and **Enter the server's address.**
  - Notices: `Connected to <host>`, `Couldn't connect to <host>: <reason>`, `Lost connection to <host>, retrying…`.
  - Reasons: timeout **The server didn't answer within 10 seconds.**; `NSURLErrorNotConnectedToInternet` **LiveSplit One for macOS needs local network access. Allow it in System Settings › Privacy & Security › Local Network.**; anything else `error.localizedDescription`.
- **Log lines** (spec §12.1), in `CONNECTION` unless named: `Connecting to <url>`, `Connected to <host>`, `Disconnected from <host>`, `Lost connection to <host>: <reason>`, `Retrying <host> in <n> s`, `Retry failed: <reason>`, `Received <message>, replied <reply>`, `Received a binary message, replied <reply>`, `Sent <event>`, and in `ERROR` `Couldn't connect to <host>: <reason>`. A `GameTimeLogFilter` per connection decides for a message's `Received` line and its events' `Sent` lines together; the message is still applied and answered.
- **Accessibility identifiers:** menu items `timer-connect` (right-click) and `file-connect` (menu bar); sheet `connect-sheet`, `connect-url`, `connect-error`, `connect-button`, `connect-cancel`.
- `app.toml`: `last_server_url` saved on Connect (`settings.update { $0.lastServerURL = text }`), prefilled from it (#49's comment). Nothing else.
- Never connect at launch (spec §8.3).

## Review Focus

1. **Nothing waits where it mustn't.** `report` never blocks; the main thread never waits on a queue; a server reset that asks doesn't freeze menus (they get `Busy`, logged). Tests in Tasks 4 and 5.
2. **Generations.** A late reply, close or retry timer from an old connection never touches the new one, and Disconnect during Connecting or a retry wait leaves nothing running. Tests in Task 5.
3. **Reconnection timing** follows 1, 2, 4, 8, 16, 30, 30 … and restarts after a success; a failed first attempt never retries. Tests in Tasks 2 and 5.
4. **Wire order:** event before reply, replies in order. Integration test in Task 5.

## Spec changes this pull request makes

Commit the rewrite of §8 and the §12.1 rows (made when this plan was written) with this plan. During the work, if the spec is wrong, fix it here and list the change in the description.

## Left to later issues

Post each as a comment on the issue named, once the pull request is open, and list it in the description:

- **#41:** screenshots of the Connect sheet and of the `Connected to` notice, for Connecting to a Server and Getting Started.
- **#18:** the Connect flow from §14.3 is added by Task 7; tick it on #18.
- **#15:** Edit Splits replaces the run while a server may be connected; nothing to do in the client, but the splits editor's OK must not run while a server command is mid-flight (it runs on the main thread under the write lock, which is enough).

---

### Task 1: `ServerURL`: what the user typed, as a URL and a host

**Files:**
- Create: `App/Server/ServerURL.swift`
- Test: `Tests/Unit/ServerURLTests.swift`

```swift
import Foundation

/// A server address the user typed into the Connect sheet (spec §8.1).
struct ServerURL: Equatable, Sendable {
    let url: URL
    /// What the menu, notices and log call the server: the host, with `:<port>` if the URL names one.
    let host: String

    enum Problem: Error, Equatable {
        case scheme, host
        var message: String {
            switch self {
            case .scheme: "Use a ws:// or wss:// address."
            case .host: "Enter the server's address."
            }
        }
    }

    static func parse(_ text: String) -> Result<ServerURL, Problem> {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "ws://" + text }
        guard let components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased()
        else { return .failure(.host) }
        guard scheme == "ws" || scheme == "wss" else { return .failure(.scheme) }
        guard let host = components.host, !host.isEmpty, let url = components.url
        else { return .failure(.host) }
        let shown = components.port.map { "\(host):\($0)" } ?? host
        return .success(ServerURL(url: url, host: shown))
    }
}
```

`URLComponents.host` returns IPv6 hosts without brackets; show them with brackets when a port follows (`[::1]:9087`). Check what it gives and adjust.

- [ ] **Tests first:** `192.168.1.20:9087` → `ws://192.168.1.20:9087`, host `192.168.1.20:9087`; `wss://example.com/path` keeps the path, host `example.com`; ` ws://a:1 ` trims; `WS://a` accepted; `http://a` → `.scheme`; `ws://` and `ws://:9087` → `.host`; `[::1]:9087` → host `[::1]:9087`. Run, see them fail, implement, see them pass.
- [ ] Commit: `feat: parse server addresses for Connect to Server`

### Task 2: Connection status and retry timing

**Files:**
- Create: `App/Server/ConnectionStatus.swift`, `App/Server/ReconnectDelays.swift`
- Test: `Tests/Unit/ConnectionStatusTests.swift`, `Tests/Unit/ReconnectDelaysTests.swift`

```swift
/// Where the connection is (spec §8.3).
enum ConnectionStatus: Equatable, Sendable {
    case notConnected
    case connecting(ServerURL)
    case connected(ServerURL)
    /// Lost after being open; `attempt` counts retries since, from 0.
    case retrying(ServerURL, attempt: Int)

    /// The menu item's title (spec §8.3).
    var menuTitle: String {
        switch self {
        case .notConnected: "Connect to Server…"
        case .connecting(let s), .connected(let s), .retrying(let s, _): "Disconnect from \(s.host)"
        }
    }
}

/// The waits before each retry after a lost connection: 1, 2, 4, 8, 16, then 30 s for ever (spec §8.3).
enum ReconnectDelays {
    static func delay(beforeRetry attempt: Int) -> Duration {
        .seconds(attempt < 5 ? 1 << attempt : 30)
    }
}
```

- [ ] **Tests first:** delays for attempts 0…7 are 1, 2, 4, 8, 16, 30, 30, 30; a huge attempt number is 30 (no overflow); each status's `menuTitle`. Implement. Pass.
- [ ] Commit: `feat: add the connection status and reconnection delays`

### Task 3: `WebSocket`, `URLSessionWebSocket` and the fake server

**Files:**
- Create: `App/Server/WebSocket.swift`, `App/Server/URLSessionWebSocket.swift`
- Create: `Tests/Support/FakeServer.swift`, listed in `project.yml` in the sources of `LiveSplitOneIntegrationTests` and `LiveSplitOneE2ETests`
- Test: `Tests/Integration/URLSessionWebSocketTests.swift`

```swift
/// What `ServerClient` needs from a WebSocket connection. Callbacks may come on any thread.
protocol WebSocket: AnyObject, Sendable {
    /// Starts connecting. Exactly one of `opened` or `ended` comes first; after `opened`,
    /// `received` for each message in order, then `ended` once, unless `close()` was called.
    func start(events: WebSocketEvents)
    /// Queues a text frame. Never blocks.
    func send(_ text: String)
    /// Closes with a normal close code (1000). No callback follows.
    func close()
}

struct WebSocketEvents: Sendable {
    var opened: @Sendable () -> Void
    var received: @Sendable (WebSocketMessage) -> Void
    /// Why it ended, already as the text the user sees (spec §8.1).
    var ended: @Sendable (String) -> Void
}

enum WebSocketMessage: Equatable, Sendable { case text(String), binary }

/// Makes a socket for a URL; tests pass a fake.
typealias WebSocketFactory = @Sendable (URL) -> WebSocket
```

`URLSessionWebSocket`:

- One `URLSession` per socket, `URLSessionConfiguration.ephemeral`, a delegate (`URLSessionWebSocketDelegate`) as in `scripts/handshake-check.swift`, `delegateQueue` a private serial `OperationQueue`. No `Origin` header (spec §8.1). Invalidate the session when the socket ends or closes.
- **Handshake timeout:** its own 10 s timer from `start`; if `didOpenWithProtocol` hasn't come, cancel and end with **The server didn't answer within 10 seconds.** Don't rely on `timeoutIntervalForRequest` for the handshake; set `timeoutIntervalForRequest` to a large value (1 day), since on a WebSocket task it can also end an idle connection. Check this in the test below.
- **Reasons:** `NSURLErrorNotConnectedToInternet` → the local network text; `NSURLErrorTimedOut` → the timeout text; else `localizedDescription`. A close from the server: `The server closed the connection.` Put the mapping in a `static func reason(for error: Error) -> String`, unit tested.
- **Receive loop** as in the script; `.data` → `.binary`.
- **Ping:** after opening, every `pingInterval` (10 s) call `sendPing`; if its handler hasn't run `pongTimeout` (10 s) later, cancel and end with `The server stopped answering.` Both intervals are init parameters, so tests can make them short.
- One `Mutex`-guarded state (`idle`, `opening`, `open`, `ended`), so `ended` is reported once and nothing is reported after `close()`.

`FakeServer` (tests only): an `NWListener` on `127.0.0.1`, port 0 (read the real port once `.ready`), with `NWProtocolWebSocket.Options` (`autoReplyPing = true`, settable to `false` for the ping test). It records each received text message in order, can `send(_:)` a text or binary message to the open connection, `dropConnections()` (cancel them, as a crash would), `stop()`, and `accepting = false` to refuse new connections (cancel them at once). `url` gives `ws://127.0.0.1:<port>`. `waitForMessage(where:timeout:)` and `waitForConnection(timeout:)` poll without blocking the main thread. It answers nothing on its own: it is the server, the app is the client.

- [ ] **Integration tests first** (`URLSessionWebSocketTests`): opens and receives a message from the fake server; a sent text arrives; `close()` reaches the server as a normal close and no `ended` follows; `dropConnections()` gives `ended`; connecting to a port nobody listens on gives `ended` with macOS's reason and no `opened`; a listener that never answers the handshake (a plain `NWListener` with TCP only) gives the timeout text (inject a 1 s handshake timeout); with `autoReplyPing = false` and 0.5 s ping and pong times, `ended` says the server stopped answering; with ping 0.5 s and auto-reply on, the connection stays open for 3 s idle.
- [ ] Unit test `reason(for:)` with `URLError(.notConnectedToInternet)`, `URLError(.timedOut)` and `URLError(.cannotConnectToHost)`.
- [ ] Commit: `feat: add the WebSocket connection and a fake server for tests`

### Task 4: `CommandRunner` shares its sink and its events

**Files:**
- Modify: `App/Menu/CommandRunner.swift`
- Test: `Tests/Unit/CommandRunnerTests.swift`

- Expose the sink: `let sink: EventSink` (was private). Server messages call `sink.handleCommand` on the server's queue (#56's comment, its second option). Don't add `CommandSource.server`: server commands are logged by `ServerClient` in `CONNECTION` (spec §12.1, as rewritten), so the comment on `CommandSource` that says #14 adds it goes.
- Add an event observer, set once by the app delegate after the client exists:

```swift
/// Called with every event the sink reports, from any source, on the command's thread. Must
/// return at once and never call the sink (`EventSink.Report`).
func observeEvents(_ observer: @escaping @Sendable (TimerEvent) -> Void) {
    eventObserver.withLock { $0 = observer }
}
```

`eventObserver` is a `Mutex<(@Sendable (TimerEvent) -> Void)?>` held in a `Sendable` box, as `ResetPreference` is. The sink's `report` becomes: `if case .event(let event?) = result { eventObserver.value?(event) }`, then the existing hop to the main actor. Errors and unknown events send nothing (LiveSplit One sends only events).

- [ ] **Tests first:** a menu split reports `.started` to the observer once; a rejected command reports nothing; a command run with `sink.handleCommand` from another thread reports to the same observer.
- [ ] Commit: `refactor: share the command sink and its events with the server client`

### Task 5: `ServerClient`

**Files:**
- Create: `App/Server/ServerClient.swift`
- Test: `Tests/Unit/ServerClientTests.swift` (fake `WebSocket`, manual schedule), `Tests/Integration/ServerClientTests.swift` (real socket, real livesplit-core, `FakeServer`)

```swift
/// The connection to a LiveSplit One server (spec §8).
@MainActor
final class ServerClient {
    typealias Schedule = NoticeQueue.Schedule

    private(set) var status: ConnectionStatus = .notConnected { didSet { onStatusChange?(status) } }
    var onStatusChange: ((ConnectionStatus) -> Void)?

    init(
        sink: EventSink, notices: @escaping @MainActor (String) -> Void, log: Log = .shared,
        makeSocket: @escaping WebSocketFactory = URLSessionWebSocket.init(url:),
        schedule: @escaping Schedule = NoticeQueue.afterDelay)

    func connect(to server: ServerURL)
    func disconnect()
    /// Called with every event, on any thread (`CommandRunner.observeEvents`).
    nonisolated func send(_ event: TimerEvent)
}
```

Behaviour (spec §8.2, §8.3):

- `connect` (only from `.notConnected`): bump `generation`, make a socket, status `.connecting`, log `Connecting to <url>`, `start` it with callbacks that hop to the main actor (`Task { @MainActor in … }`) and check the generation first.
- `opened`: status `.connected`, notice and log `Connected to <host>`, new `GameTimeLogFilter`, publish the socket for sending (see below).
- `ended(reason)`:
  - from `.connecting` (first attempt): status `.notConnected`, notice `Couldn't connect to <host>: <reason>`, `ERROR` log line. No retry.
  - from `.connected`: log `Lost connection to <host>: <reason>`, notice `Lost connection to <host>, retrying…`, status `.retrying(attempt: 0)`, schedule the retry.
  - from `.retrying` (a retry that failed): log `Retry failed: <reason>`, attempt + 1, schedule again. No notice.
- Scheduling a retry: log `Retrying <host> in <n> s`, `schedule(seconds) { [generation] in guard same generation, case .retrying … ; start a new socket }`. A retry keeps status `.retrying` while it connects, so a failed retry is told apart from a failed first attempt.
- `disconnect`: from any state but `.notConnected`: bump generation (cancels pending retries and stale callbacks), `close()` the socket, status `.notConnected`, log `Disconnected from <host>`. No notice.
- **Messages** (`received`): don't hop to the main actor. On the server queue, in order: check the generation still matches the published socket's; for `.text(m)`: decide `shouldLog` with the connection's filter, mark the queue's current message as quiet if not (`DispatchQueue.setSpecific`-style key read in `send(_:)`, or a value only touched on the server queue), `let reply = sink.handleCommand(m)`, log `Received <m>, replied <reply>` if logged, then `socket.send(reply)` if the generation still matches. For `.binary`: send `{"Err":{"code":"InvalidCommand"}}` and log it.
- **Sending events** (`send(_:)`, any thread): the open socket and its generation sit in a `Mutex` (`published`), set on `opened` and cleared on end or disconnect. If there is one, `socket.send(EventSink.encodeEvent(event))` and log `Sent <json>` unless the event is reported on the server queue during a quiet message. Never wait.
- `filter` lives on the server queue only (reset there on `opened`, via `queue.async`).
- **Quit:** `AppDelegate.applicationWillTerminate` calls `disconnect()` (spec §8.3).

**Unit tests** (fake socket records `start`/`send`/`close`, lets the test fire `opened`/`received`/`ended`; schedule records delays and runs them on demand; a real `EventSink` on an in-memory timer):

- [ ] Connect → `.connecting`, no notice; `opened` → `.connected`, notice `Connected to <host>`.
- [ ] First attempt ends → `.notConnected`, `Couldn't connect…` notice, no retry scheduled.
- [ ] Open connection ends → `Lost connection…` notice, retries scheduled at 1, 2, 4, 8, 16, 30, 30 s as each fails, with no further notices; then `opened` → `Connected to` notice again; a second loss starts again at 1 s.
- [ ] Disconnect while connecting, while connected and while waiting for a retry: socket closed, status `.notConnected`, the pending retry does nothing when it fires, and a late `ended` from the old socket does nothing.
- [ ] A text message runs on the sink and the reply is sent; the event it causes is sent before the reply; a binary message gets the `InvalidCommand` reply.
- [ ] Ten messages in a row get ten replies in the same order.
- [ ] A reply that finishes after Disconnect isn't sent (make the message a reset that asks, with `decideReset` waiting on a semaphore; disconnect; then answer).
- [ ] A local split (through `CommandRunner`) while connected sends `{"event":…}`; while not connected sends nothing.
- [ ] Logging: `setGameTime` three times then `pause`: one `Received … setGameTime` line, no `Sent` lines for the second and third, then the `pause` lines. A new connection starts a new filter.
- [ ] While a menu reset waits on its question, a server `split` gets a `Busy` reply at once (shows the two queues). Use #12's `ask` hook.

**Integration tests** (`FakeServer`, real `URLSessionWebSocket`, real `CommandRunner` and timer; acceptance criterion 1 on #14):

- [ ] The server's `splitOrStart` starts the timer, and the server receives the `Started` event before the reply.
- [ ] A local Split through `CommandRunner` reaches the server as an event.
- [ ] `dropConnections()` → the client retries and reconnects within 2 s (inject a schedule that shortens delays ×0.1 if needed, but keep the order checked by the unit tests), and commands work again.
- [ ] Disconnect sends a normal close; the server sees no further messages.
- [ ] A port with no listener gives `Couldn't connect to 127.0.0.1:<port>: …` and no retry.

- [ ] Commit: `feat: add the server client with automatic reconnection`

### Task 6: The Connect sheet

**Files:**
- Create: `App/Server/ConnectSheet.swift`
- Test: `Tests/HeadlessUI/ConnectSheetTests.swift`

A view controller in an `NSWindow` (`styleMask: [.titled]`) shown with `timerWindow.beginSheet`, laid out with Auto Layout as `SettingsViewController` is: **Server address:** label, the URL field (`connect-url`, 320 pt wide, prefilled), the error label (`connect-error`, hidden while empty, system red), **Cancel** (`connect-cancel`, key equivalent Esc) and **Connect** (`connect-button`, default, Return, disabled while the field is empty after trimming).

```swift
@MainActor
final class ConnectSheet: NSViewController, NSTextFieldDelegate {
    /// `connect` gets the parsed URL and the text as typed (trimmed), for `app.toml`.
    init(prefill: String?, connect: @escaping (ServerURL, String) -> Void, cancel: @escaping () -> Void)
}
```

Connect parses with `ServerURL.parse`: on failure it shows the message and keeps the sheet open; on success it calls `connect`. Typing clears the error.

- [ ] **Tests first:** prefill shows; empty field disables Connect; `http://x` then Connect shows **Use a ws:// or wss:// address.** and doesn't call `connect`; typing clears it; `192.168.1.20:9087` then Connect calls `connect` with `ws://192.168.1.20:9087` and the trimmed text; Cancel calls `cancel`. Check through the accessibility tree, as the Settings window tests do.
- [ ] Commit: `feat: add the Connect to Server sheet`

### Task 7: Menus, app wiring and the E2E flow

**Files:**
- Modify: `App/Menu/TimerMenus.swift`, `App/AppDelegate.swift`
- Create: `Tests/E2E/ConnectTests.swift`
- Modify: `Tests/E2E/E2EApp.swift` (nothing new expected; the app connects to the fake server on `127.0.0.1` as a user would, by typing its URL)
- Test: `Tests/Unit/TimerMenusTests.swift`

- `TimerMenus` gets `connectionStatus: @MainActor () -> ConnectionStatus` in its init and one action, `AppDelegate.toggleConnection(_:)`. Right-click menu: a new item after **Save Layout As…**'s separator group, before **Always on Top**, in its own group: `… Save Layout As… / ─── / Connect to Server… / Always on Top / ─── …` (spec §7's order). Menu bar: the File menu, below **Save Layout As…**, after a separator. `validateMenuItem` sets its title from `connectionStatus().menuTitle`; always enabled.
- `AppDelegate`:
  - creates `ServerClient(sink: runner.sink, notices: { timerWindow.notices.show($0) })` and `runner.observeEvents { [client] in client.send($0) }`;
  - `toggleConnection`: if `.notConnected`, shows `ConnectSheet` with `settings.settings.lastServerURL`; on Connect ends the sheet, `settings.update { $0.lastServerURL = text }`, `client.connect(to:)`. Otherwise `client.disconnect()`.
  - `applicationWillTerminate`: `client.disconnect()`.
- Menu titles in `TimerMenusTests` for each status.

**E2E** (`ConnectTests`, spec §14.3; one main-path test, under 60 s):

- [ ] Start a `FakeServer`. Launch. Right-click → **Connect to Server…**, type its URL, **Connect**. Expect the `Connected to 127.0.0.1:<port>` notice in the window.
- [ ] The server sends `{"command":"splitOrStart"}`: the server receives `{"success":null}` and the `Started` event; the window's timer runs.
- [ ] Right-click → Control → **Split**: the server receives the `Splitted` event.
- [ ] `dropConnections()`: the window shows `Lost connection to …, retrying…`, then `Connected to …` within 5 s.
- [ ] Right-click → **Disconnect from 127.0.0.1:<port>**: the server sees the close; the menu shows **Connect to Server…** again; `app.toml` has `last_server_url`.
- [ ] Commit: `feat: connect to a server from the menus`

### Task 8: The wiki, the manual check, every check, and the pull request

**Files:**
- Create: `docs/wiki/Connecting-to-a-Server.md` (spec §16.2: connecting to livesplit-asr-bridge, which address to use, local network access and where to allow it, each notice, automatic reconnection, Disconnect, servers other than the bridge)
- Modify: `docs/wiki/_Sidebar.md` (after Splits and Layouts, per §16.2), `docs/wiki/Home.md` (link), `docs/wiki/The-Menu.md` (the item in both menus, linking to the new page), `docs/wiki/The-Timer-Window.md` (the three connection notices), `docs/wiki/Getting-Started.md` (the last step: connect to the bridge, from #12's page), `docs/wiki/Settings-and-Logs.md` (`last_server_url`, the Connection lines), `docs/wiki/Troubleshooting.md` (**needs local network access**; **didn't answer within 10 seconds** on a LAN address: the PC's firewall for the bridge's port, or a VPN address such as Tailscale's (#7's comment); **stopped answering** after the PC sleeps)

- [ ] Write the pages. Check every bold name against `App/`. Run `scripts/wiki/check.sh docs/wiki`.
- [ ] **Manual check (acceptance criterion 2, spec §14.4):** the real livesplit-asr-bridge on the gaming PC, over Tailscale and the LAN address: connect, run a real game with its auto splitter for a few splits, split once from the keyboard and see the bridge log the event, stop the bridge and start it again (the app reconnects), put the PC to sleep (the app notices within 20 s and retries), Disconnect. Also on a fresh user account or after `tccutil reset LocalNetwork`: deny the local network prompt (the local network notice), then allow it (connects). Write what was seen in the pull request.
- [ ] Run every check in `CONTRIBUTING.md` step 4. Commit `docs: document connecting to a server`, push, open the pull request from the template, listing the spec changes, the later-issue comments and the screenshots #41 needs (the Connect sheet, the menu with **Disconnect from …**).
