# Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the Xcode project, the Rust core with livesplit-core's C API and the server protocol additions, the Swift bindings, the bridge handshake check, the pull request checks, the release pipeline and Renovate, so every later feature is built, checked, released and kept up to date the same way.

**Architecture:** XcodeGen generates the Xcode project from `project.yml`. An empty AppKit app links `LiveSplitCore`, a static library target holding livesplit-core's generated Swift bindings and a hand-written wrapper. Its build phase runs `scripts/build-core.sh`, which builds the `core/` Rust crate, whose dependency on `livesplit-core-capi` makes Cargo build the C API's static library in the same build, and regenerates the bindings with livesplit-core's `bind_gen`. GitHub Actions run the checks on every pull request, and on every merge to `main` a release workflow, copied from livesplit-asr-bridge, publishes a release candidate and, after approval, the full release.

**Tech Stack:** Swift 6, AppKit, Swift Testing, XCTest (XCUITest), Xcode 26.6 or newer (27.0 locally, 26.6 in CI), XcodeGen, Rust (stable, edition 2024), livesplit-core at upstream revision `61070c47ea91e6e148d6801cb7a03e8e32a2ebc9`, `futures-executor` 0.3, GitHub Actions, git-cliff, mise, Renovate, bash, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (sections 3, 4, 5.3, 8.1, 14.1, 15 and 17). Issues: #5, #6, #7, #8, #9, #10. This plan is issue #4.

## Before you start

- **Issue #2 is merged first.** It adds `AGENTS.md`, `CONTRIBUTING.md`, the issue forms, the pull request template, the licenses, `commitlint.config.mjs`, `mise.toml` (git-cliff, shellcheck, actionlint, xcodegen) and `.gitignore`. Tasks here edit some of them; they never recreate them.
- **The Mac needs full Xcode.** The maintainer's Mac only has the Command Line Tools (`xcode-select -p` prints `/Library/Developer/CommandLineTools`, and `/Applications` has no Xcode). `xcodebuild`, XcodeGen projects and XCUITest need Xcode. (Swift Testing does work with the Command Line Tools, but only with extra `-F`/`-rpath` flags, and the plan always runs tests through `xcodebuild`.) The maintainer installs the current Xcode from the App Store, 27.0 as of October 2026, which needs macOS 26.6 or newer, then:

  ```bash
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  xcodebuild -runFirstLaunch
  xcodebuild -version   # Expected: Xcode 26.6 or newer (27.0 from the App Store)
  ```

- **Other tools:** rustup (installed through Homebrew on the maintainer's Mac; `scripts/build-core.sh` also looks in `/opt/homebrew/opt/rustup/bin`), mise (`brew install mise`, then `mise install` in the repository), and `jq`, which macOS ships at `/usr/bin/jq`.
- **Shell setup for agents on this Mac:** `export PATH="$(brew --prefix rustup)/bin:$HOME/.cargo/bin:$PATH"`.

## Global Constraints

- Names (spec §3): repository, config and log folder `livesplit-one-macos`; display name `LiveSplit One for macOS`; `CFBundleName` `LiveSplit One` (15 characters at most); bundle identifier `dev.alexcosta.livesplit-one-macos`; macOS 14 or newer.
- The app bundle is `LiveSplit One.app`; the Xcode target and Swift module are `LiveSplitOne`.
- livesplit-core comes from `https://github.com/LiveSplit/livesplit-core`, pinned to `rev = "61070c47ea91e6e148d6801cb7a03e8e32a2ebc9"` for both `livesplit-core` and `livesplit-core-capi`. Never a fork, never a branch (spec §4).
- `core/Cargo.toml`: package `lso-core`, `license = "MIT OR Apache-2.0"` (spec §18), `crate-type = ["staticlib"]`, `rust-version = "1.95"` (livesplit-core's own `rust-version`).
- No LTO for `core/`: the C API's library and core's library share one compilation of livesplit-core (Task 2, key facts), which LTO would split.
- Generated files are never edited or committed: `LiveSplitCore/Generated/`, `LiveSplitCore/CLiveSplitCore/include/livesplit_core.h`, `LiveSplitCore/lib/`, `LiveSplitOne.xcodeproj`, `App/Info.plist` (spec §4, §4.1).
- The build-time version: `LSO_VERSION` (full, for example `0.4.0-rc.2`) and `MARKETING_VERSION` (`X.Y.Z` only), passed to `xcodebuild`. Without them, the app is `0.0.0-dev`. No version-bump commits (spec §4.2, §15).
- Full release tags match `vX.Y.Z`; release candidates are `vX.Y.Z-rc.N` and never count as the previous version. The first release is 0.1.0 (spec §15).
- Allowed commit and pull request title types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `style`, `chore` (CONTRIBUTING.md).
- Swift is formatted with `swift format` using `.swift-format` (4 spaces, 100 columns) and must pass `swift format lint --strict`. Generated Swift is never linted.
- Action versions: `actions/checkout@v7`, `Swatinem/rust-cache@v2`, `jdx/mise-action@v4`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `amannn/action-semantic-pull-request@v6`, `wagoid/commitlint-github-action@v6` (as in livesplit-asr-bridge). Since issue #36, every action is pinned to a full commit SHA with the exact version as a comment, and Renovate updates the pins (spec §15); the tags above are the versions the plan was written against. Tool versions live only in `mise.toml`; Rust comes only from `rust-toolchain.toml`.
- CI jobs run on `macos-latest` (spec §15), except `commitlint` and `pr-title`, and the release jobs that only run git-cliff and `gh`, which run on `ubuntu-latest`.
- Every commit is signed and follows Conventional Commits; branches are `<type>/<short-description>`; each task is one pull request that links its issue (`Closes #N`, or `Part of #N` when a later task closes it). The implementer stops after opening the pull request: only the maintainer merges.
- Pull request descriptions follow `.github/pull_request_template.md`: the issue, what changed and why, how it was tested (the commands run and their results), and the checklist ticked. Write it to a file outside the repository (`PR_BODY=$(mktemp)`) and pass it with `--body-file "$PR_BODY"`.

## Review Focus

1. **A server command arriving while a reset question is open** (for example the bridge sends `split` while the user looks at "Update best times?"): it gets `{"error":{"code":"Busy"}}` at once, the timer is not locked, so the window keeps drawing, and the question's answer still applies. Test in Task 2.
2. **Bytes that aren't a valid command** (invalid UTF-8, a null pointer, text that isn't JSON): the reply is an `InvalidCommand` error, never a crash. A Rust panic inside an `extern "C"` function aborts the whole app. Test in Task 2.
3. **A release candidate version in the bundle:** `CFBundleShortVersionString` only takes `X.Y.Z`, so `0.4.0-rc.2` must land in `LSOVersion` and `0.4.0` in `CFBundleShortVersionString`, and an empty `LSO_VERSION` must fall back to `0.0.0-dev`, not show nothing. Tests in Task 1; checked on every packaged build by `scripts/build-app.sh` (Task 5).
4. **Building twice with no change on the Rust side:** Xcode skips the "Build core and bindings" phase; editing one `.rs` file in `core/src` runs it again. Getting this wrong either rebuilds Rust on every Swift edit or ships stale bindings. Check in Task 3, Step 9.
5. **The `EventSink` Swift object outliving the caller's `SharedTimer` handle:** the sink keeps its own handle, so commands still work after the caller drops theirs. Tests in Task 2 (Rust) and Task 3 (Swift).

Two conditions can't be tested before the first real release, and are checked then (Task 6, Step 9): a newer merge cancels an older release candidate that is still waiting for approval, and the downloaded `.app` opens on both Apple Silicon and Intel after Open Anyway.

## Spec changes these pull requests make

Each is made in the pull request named, and listed in its description:

- §4, §4.1 (Task 3): `LiveSplitCore/` is an Xcode static library target, not a Swift package, because Xcode builds Swift packages before any of the project's build phases, so the phase in §4.2 could not regenerate the bindings before they are compiled.
- §4.2 (Task 1): the full version goes in `LSOVersion`; `CFBundleShortVersionString` holds `X.Y.Z`, since bundle versions must be numeric.
- §8.1 (Task 4): which `Origin` the client sends, and why.
- §15 (Task 7): Renovate also reads `project.yml`'s Swift packages, through a custom manager, since Renovate's Swift manager only reads `Package.swift`.

## Found while planning, left for the maintainer

Not changed by this plan, because each changes the design or belongs to a later issue:

- **The renderer's size hint (spec §5.2) isn't in the C API.** livesplit-core's `BorrowedRenderer::render` returns `Option<[f32; 2]>`, the new ideal size (`src/rendering/software.rs:268-276`), but the C API's `SoftwareRenderer_render` returns nothing (`capi/src/software_renderer.rs:35-55`). The timer window issue needs one more `core/` function that renders and returns the hint; spec §5.3 should list it.
- **Global hotkeys (backlog) would bypass the event sink.** The C API's hotkey system takes its own `CommandSink`, which Swift can only create from a plain `SharedTimer` (`CommandSink_from_timer`, `capi/src/command_sink.rs:29-33`; its inner type is `pub(crate)`, line 23), so hotkey commands wouldn't be reported or ask about resets. That issue will need a `core/` addition.
- **The app icon** (`assets/brand/icons/icon.icns`, `CFBundleIconFile`, spec §3) has no foundation issue; `project.yml` leaves it out until it exists.
- **The binary-message reply** in spec §8.2, `{"Err":{"code":"InvalidCommand"}}`, is LiveSplit One's (`src/api/LiveSplitServer.ts:62`), but every other error reply is `{"error":{"code":…}}` (`server_protocol.rs:82-87`, `rename_all = "camelCase"`), so a server may not recognise it. Copying LiveSplit One is still what the spec asks for.

---

### Task 1: Xcode project and an empty app (issue #5)

**Branch:** `feat/app-scaffold` · **PR title:** `feat: add the Xcode project and an empty app` · **PR body:** `Closes #5`, using the pull request template.

**Files:**
- Create: `project.yml` (the XcodeGen project: app and the four test targets)
- Create: `rust-toolchain.toml` (Rust for `core/`, from Task 2 on)
- Create: `.swift-format` (Swift formatting rules)
- Create: `App/AppDelegate.swift` (entry point and the empty window)
- Create: `App/AppVersion.swift` (the version shown in the app)
- Create: `Tests/Unit/AppVersionTests.swift`
- Create: `Tests/HeadlessUI/TimerWindowTests.swift`
- Create: `Tests/Integration/AppBundleTests.swift`
- Create: `Tests/E2E/LaunchTests.swift`
- Modify: `.gitignore`, `CONTRIBUTING.md`, `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (§4.2)

**Interfaces:**
- Consumes: `mise.toml` with `xcodegen` (issue #2).
- Produces:
  - Xcode targets `LiveSplitOne` (product `LiveSplit One.app`, module `LiveSplitOne`), `LiveSplitOneUnitTests`, `LiveSplitOneHeadlessUITests`, `LiveSplitOneIntegrationTests`, `LiveSplitOneE2ETests`; scheme `LiveSplitOne` with all four test targets.
  - `AppDelegate.makeWindow() -> NSWindow` (static, `@MainActor`); the window's accessibility identifier is `timer-window`.
  - `AppVersion.current: String`, `AppVersion.resolve(_ value: Any?) -> String`, `AppVersion.fallback = "0.0.0-dev"`, `AppVersion.infoKey = "LSOVersion"`.
  - Build settings `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `LSO_VERSION`, set on the `xcodebuild` command line by Task 5's `scripts/build-app.sh`.

Key facts, checked with XcodeGen 2.46.0:
- A `bundle.unit-test` target that depends on the app gets `TEST_HOST` set automatically, from the target name (`LiveSplitOne.app/Contents/MacOS/LiveSplitOne`), which is wrong here because the product is named `LiveSplit One`. The hosted test targets set `TEST_HOST` explicitly, and the integration target sets it to `""` so it isn't hosted.
- `info:` makes XcodeGen write `App/Info.plist` on every `xcodegen generate`, so it is ignored, like the project.
- `CODE_SIGN_IDENTITY: "-"` signs ad hoc. The build is still unsigned in the sense of spec §2 (no Developer ID), but an Apple Silicon Mac runs only signed code, and an ad-hoc sealed bundle can be opened with Open Anyway.

- [ ] **Step 1: Write the toolchain, formatting and ignore rules**

`rust-toolchain.toml`:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
# Both Mac architectures, for the universal release build (spec §4.2).
targets = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
```

`.swift-format`:

```json
{
    "version": 1,
    "indentation": { "spaces": 4 },
    "lineLength": 100
}
```

Add to `.gitignore` (keep what issue #2 put there; add only the lines that are missing):

```
/LiveSplitOne.xcodeproj/
/App/Info.plist
/build/
/dist/
```

- [ ] **Step 2: Write `project.yml`**

```yaml
# The Xcode project (spec §4.1). Generate it with `xcodegen generate`; the
# generated LiveSplitOne.xcodeproj and App/Info.plist are not committed.
name: LiveSplitOne
options:
  bundleIdPrefix: dev.alexcosta
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    # Unsigned builds (spec §2), ad-hoc signed so they run on Apple Silicon.
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
    # Development fallbacks. Releases pass the real version to xcodebuild
    # (spec §4.2), so no committed file holds a release's version.
    MARKETING_VERSION: "0.0.0"
    CURRENT_PROJECT_VERSION: "0"
    LSO_VERSION: 0.0.0-dev
targets:
  LiveSplitOne:
    type: application
    platform: macOS
    sources: [App]
    info:
      path: App/Info.plist
      properties:
        CFBundleName: LiveSplit One
        CFBundleDisplayName: LiveSplit One for macOS
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        # The full version, such as 0.4.0-rc.2, which
        # CFBundleShortVersionString can't hold. The app shows this one.
        LSOVersion: $(LSO_VERSION)
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSPrincipalClass: NSApplication
        NSHighResolutionCapable: true
        NSLocalNetworkUsageDescription: >-
          LiveSplit One connects to the timer server you choose, such as
          livesplit-asr-bridge on another computer.
    settings:
      base:
        PRODUCT_NAME: LiveSplit One
        PRODUCT_MODULE_NAME: LiveSplitOne
        PRODUCT_BUNDLE_IDENTIFIER: dev.alexcosta.livesplit-one-macos
    scheme:
      testTargets:
        - LiveSplitOneUnitTests
        - LiveSplitOneHeadlessUITests
        - LiveSplitOneIntegrationTests
        - LiveSplitOneE2ETests

  # The test pyramid (spec §14.1). Unit and headless UI tests run inside the
  # app, so they can use its internals.
  LiveSplitOneUnitTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/Unit]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/LiveSplit One.app/Contents/MacOS/LiveSplit One
        BUNDLE_LOADER: $(TEST_HOST)
  LiveSplitOneHeadlessUITests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/HeadlessUI]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/LiveSplit One.app/Contents/MacOS/LiveSplit One
        BUNDLE_LOADER: $(TEST_HOST)
  # Not hosted: it checks the built app from outside, and links LiveSplitCore
  # itself once that exists.
  LiveSplitOneIntegrationTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/Integration]
    dependencies:
      - target: LiveSplitOne
        link: false
    settings:
      base:
        # XcodeGen would otherwise host it in the app, by target name.
        TEST_HOST: ""
        BUNDLE_LOADER: ""
  LiveSplitOneE2ETests:
    type: bundle.ui-testing
    platform: macOS
    sources: [Tests/E2E]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_TARGET_NAME: LiveSplitOne
```

- [ ] **Step 3: Write the failing tests**

`Tests/Unit/AppVersionTests.swift`:

```swift
import Testing

@testable import LiveSplitOne

@Suite struct AppVersionTests {
    @Test func usesTheBuildVersionWhenSet() {
        #expect(AppVersion.resolve("1.2.3-rc.4") == "1.2.3-rc.4")
    }

    @Test func fallsBackWhenUnset() {
        #expect(AppVersion.resolve(nil) == AppVersion.fallback)
    }

    @Test func fallsBackWhenSetButEmpty() {
        #expect(AppVersion.resolve("") == AppVersion.fallback)
    }

    @Test func fallsBackWhenNotAString() {
        #expect(AppVersion.resolve(42) == AppVersion.fallback)
    }

    @Test func theBuiltAppHasAVersion() {
        #expect(!AppVersion.current.isEmpty)
    }
}
```

`Tests/HeadlessUI/TimerWindowTests.swift`:

```swift
import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerWindowTests {
    @Test func theWindowIsNamedForAccessibility() {
        let window = AppDelegate.makeWindow()
        #expect(window.accessibilityIdentifier() == "timer-window")
        #expect(window.title == "LiveSplit One")
    }

    @Test func theWindowIsNotShownUntilAsked() {
        #expect(!AppDelegate.makeWindow().isVisible)
    }
}
```

`Tests/Integration/AppBundleTests.swift`:

```swift
import Foundation
import Testing

private final class Marker {}

/// The built app's Info.plist. Xcode puts the app next to this test bundle.
private func appInfo() throws -> [String: Any] {
    let url = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()
        .appendingPathComponent("LiveSplit One.app")
    return try #require(Bundle(url: url)?.infoDictionary)
}

/// Checks the built app's Info.plist against spec §3 and §8.1.
@Suite struct AppBundleTests {
    @Test func namesAndIdentifierMatchTheSpec() throws {
        let info = try appInfo()
        #expect(info["CFBundleName"] as? String == "LiveSplit One")
        #expect(info["CFBundleDisplayName"] as? String == "LiveSplit One for macOS")
        #expect(info["CFBundleIdentifier"] as? String == "dev.alexcosta.livesplit-one-macos")
    }

    @Test func theMenuBarNameFitsInFifteenCharacters() throws {
        let name = try #require(try appInfo()["CFBundleName"] as? String)
        #expect(name.count <= 15)
    }

    @Test func asksForLocalNetworkAccess() throws {
        let reason = try appInfo()["NSLocalNetworkUsageDescription"] as? String
        #expect(try #require(reason).contains("livesplit-asr-bridge"))
    }

    @Test func aLocalBuildHasTheDevelopmentVersion() throws {
        let info = try appInfo()
        #expect(info["LSOVersion"] as? String == "0.0.0-dev")
        #expect(info["CFBundleShortVersionString"] as? String == "0.0.0")
    }
}
```

`Tests/E2E/LaunchTests.swift`:

```swift
import XCTest

/// E2E tests drive the app only through what a user does and sees (spec §14.1).
final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTheTimerWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows["timer-window"].waitForExistence(timeout: 10))
    }
}
```

Create `App/AppDelegate.swift` with only enough to build:

```swift
import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {}
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run:

```bash
mise x -- xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
```

Expected: build fails with `cannot find 'AppVersion' in scope` and `type 'AppDelegate' has no member 'makeWindow'`.

- [ ] **Step 5: Implement the app**

`App/AppVersion.swift`:

```swift
import Foundation

/// The app's version, embedded at build time by the release pipeline (spec
/// §4.2). Local builds show the fallback.
enum AppVersion {
    /// The Info.plist key holding the full version, such as `0.4.0-rc.2`.
    /// `CFBundleShortVersionString` can only hold `0.4.0`.
    static let infoKey = "LSOVersion"
    static let fallback = "0.0.0-dev"

    static var current: String { resolve(Bundle.main.object(forInfoDictionaryKey: infoKey)) }

    /// The build's version when it is a non-empty string, otherwise the fallback.
    static func resolve(_ value: Any?) -> String {
        guard let version = value as? String, !version.isEmpty else { return fallback }
        return version
    }
}
```

Replace `App/AppDelegate.swift`:

```swift
import AppKit

/// Starts the app and opens its single window. No storyboards: everything is
/// built in code (spec §4). Later issues replace the window's contents with
/// the timer (spec §6).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = Self.makeWindow()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// The empty timer window.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiveSplit One"
        window.setAccessibilityIdentifier("timer-window")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
mise x -- xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
swift format lint --strict --recursive App Tests
```

Expected: `** TEST SUCCEEDED **`: 5 unit, 2 headless UI, 4 integration and 1 E2E test pass; the lint prints nothing. The first E2E run may ask to let Xcode control the computer (Privacy & Security → Accessibility / Automation): the maintainer allows it once.

- [ ] **Step 7: Check the version comes from the build**

```bash
xcodebuild build -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  MARKETING_VERSION=1.2.3 CURRENT_PROJECT_VERSION=1.2.3 LSO_VERSION=1.2.3-rc.4
plist="build/DerivedData/Build/Products/Release/LiveSplit One.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :LSOVersion' \
  -c 'Print :CFBundleName' -c 'Print :CFBundleIdentifier' "$plist"
```

Expected: `1.2.3`, `1.2.3-rc.4`, `LiveSplit One`, `dev.alexcosta.livesplit-one-macos`. Then `rm -rf build`.

- [ ] **Step 8 (maintainer, needs a display): Launch the app**

`open "build/DerivedData/Build/Products/Debug/LiveSplit One.app"` after a Debug build (`xcodebuild build -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -derivedDataPath build/DerivedData`). Expected: an empty window titled `LiveSplit One`, a Dock icon, and `LiveSplit One` as the menu bar name. Quitting closes it.

- [ ] **Step 9: Update the spec and CONTRIBUTING**

In spec §4.2, replace the last bullet with:

```markdown
- The version is embedded at build time from the release pipeline (section
  15): `LSOVersion` in `Info.plist` holds the full version, such as
  `0.4.0-rc.2`, which the app shows, and `CFBundleShortVersionString` holds
  `0.4.0`, since bundle versions must be numbers. There are no version-bump
  commits.
```

In `CONTRIBUTING.md`, under "Development setup", make the setup steps say (adapt the numbering to what issue #2 wrote):

```markdown
1. Install Xcode from the App Store (26.6 or newer; the version CI uses is
   set in `.github/actions/setup/action.yml`), then run
   `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.
2. Install [rustup](https://rustup.rs/) and [mise](https://mise.jdx.dev/),
   then run `mise install` in the repository. Rust's version and targets come
   from `rust-toolchain.toml`.
3. Generate the Xcode project with `xcodegen generate`, and open
   `LiveSplitOne.xcodeproj`. The project is generated from `project.yml` and
   never committed: run `xcodegen generate` again after pulling changes to it.
```

- [ ] **Step 10: Commit and open the pull request**

```bash
git add project.yml rust-toolchain.toml .swift-format .gitignore App Tests CONTRIBUTING.md \
  docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md
git commit -m "feat: add the Xcode project and an empty app"
git push -u origin feat/app-scaffold
gh pr create --base main --title "feat: add the Xcode project and an empty app" --body-file "$PR_BODY"
```

Stop here. The maintainer merges.

---

### Task 2: The core crate and its C API additions (issue #6, first part)

**Branch:** `feat/core-crate` · **PR title:** `feat(core): add the core crate with the server protocol functions` · **PR body:** `Part of #6`, using the pull request template.

**Files:**
- Create: `core/Cargo.toml`, `core/Cargo.lock` (generated by the first build)
- Create: `core/src/lib.rs` (the crate root)
- Create: `core/src/sink.rs` (the event-reporting command sink and reset decisions)
- Create: `core/src/protocol.rs` (`handle_command` and `encode_event`)
- Create: `core/src/ffi.rs` (the C functions Swift calls)
- Create: `LiveSplitCore/CLiveSplitCore/include/lso_core.h` (their C declarations)
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `rust-toolchain.toml` (Task 1).
- Produces:
  - Rust: `sink::Host` (trait: `report(&self, Result)`, `decide_reset(&self) -> ResetDecision`), `sink::ResetDecision` (`Save`, `Discard`, `Cancel`), `sink::EventSink<H: Host>` (`new(SharedTimer, H)`, implements livesplit-core's `CommandSink` and `TimerQuery`), `protocol::handle_command(&EventSink<H>, &str) -> String`, `protocol::encode_event(u32) -> String`, `ffi::encode_result(Result) -> i32`.
  - C (used by Task 3): `LsoHost { void *context; void (*report)(void *, int32_t); uint8_t (*decide_reset)(void *); void (*release)(void *); }`, `void *LsoCommandSink_new(void *timer, LsoHost host)`, `void LsoCommandSink_drop(void *)`, `char const *LsoCommandSink_handle_command(void *, char const *)`, `char const *LsoServerProtocol_encode_event(uint32_t)`.
  - Result encoding: an event is its number (0 or more), an error `e` is `-1 - e`, as livesplit-core's C API (`capi/src/timer.rs:111-116`). Reset decisions: 0 keep, 1 discard, anything else don't reset, matching LiveSplit One's Yes / No / Don't Reset buttons.

Key facts, verified against livesplit-core `61070c47` and in a scratch build with Rust 1.99:
- **The C API crate can't be linked into this crate.** `capi/Cargo.toml` sets `crate-type = ["staticlib", "cdylib"]`, with no `rlib`, so `use livesplit_core_capi` fails with `no external crate`. Making it a normal dependency still makes Cargo build its `liblivesplit_core.a` in the same build, from the same compiled livesplit-core that `lso-core` uses (same crate hash), so the two static libraries are linked side by side (Task 3). In a scratch test, a C program and a Swift executable linked against both libraries, in debug and release, created a timer through the C API's `Timer_new` and `Timer_into_shared` and drove it through `LsoCommandSink_handle_command`. The libraries share about 37,000 symbols (std and livesplit-core), all from the same object files, so the linker loads each from one library; the C API's own objects only overlap with core's in the allocator shim, which is in its own object. That is why core is never built with LTO.
- **`server_protocol` is web-only in the C API:** `capi/src/lib.rs:130` gates the module with `#[cfg(all(target_family = "wasm", feature = "server-protocol"))]`, and its `server-protocol` feature needs `wasm-web`. livesplit-core itself has it on native: `src/networking/mod.rs:6-7` (`feature = "std"`), with `handle_command<S: CommandSink + TimerQuery>(&str, &S) -> String` (async) and `encode_event(Event) -> String` at `src/networking/server_protocol.rs:63-80`.
- **`SharedTimer` already implements both traits** (`src/event.rs:292-416`). Its command futures apply the command when created and return `async move { result }`, so `EventSink` reuses them for every timer rule instead of copying them. `SharedTimer::reset(None)` keeps the attempt (`save_attempt != Some(false)`, `src/event.rs:310`), like LiveSplit One's `this.timer.reset(updateSplits ?? true)`.
- **LiveSplit One's sink** (`LiveSplitOne/src/util/LSOCommandSink.ts:116-146`) asks only when `updateSplits` is undefined and `currentAttemptHasNewBestTimes()`; Don't Reset returns `RunnerDecidedAgainstReset`. While its dialog is open, the sink is locked and every command returns `Busy` (`LSOCommandSink.ts:75-77`, `LiveSplit.tsx:540-543`).
- **`futures_executor::block_on` panics when nested** (`cannot execute LocalPool executor from within another executor`). `handle_command` runs the protocol future in `block_on`, so the sink takes the `SharedTimer` futures' results with a single poll instead.
- **Commands are camelCase:** `#[serde(tag = "command", rename_all = "camelCase")]` (`server_protocol.rs:117`), so `{"command":"splitOrStart"}`, although the module's doc comment shows `SplitOrStart`.
- **System fonts:** `font-loading` is a livesplit-core feature (`Cargo.toml`, `font-loading = ["std", "default-text-engine"]`) that loads the Mac's fonts (`src/rendering/default_text_engine/mod.rs:51-52`); the C API has no feature for it. `core/` enables it on its own livesplit-core dependency, and Cargo's feature unification applies it to the C API's build too, so layouts that name system fonts render with them.

- [ ] **Step 1: Write the manifest and the first failing tests**

`core/Cargo.toml`:

```toml
[package]
name = "lso-core"
version = "0.0.0"
edition = "2024"
rust-version = "1.95"
description = "livesplit-core's C API plus the functions livesplit-one-macos adds to it."
license = "MIT OR Apache-2.0"
repository = "https://github.com/alexcosta97/livesplit-one-macos"
publish = false

[lib]
name = "lso_core"
crate-type = ["staticlib"]

# Both LiveSplit crates come from the same upstream revision (spec §4). The C
# API crate only builds as a static library (no rlib), so this crate can't use
# it. It is a dependency so that Cargo builds its liblivesplit_core.a in the
# same build, from the same compiled livesplit-core this crate uses;
# scripts/build-core.sh then links both libraries into the app.
[dependencies]
livesplit-core = { git = "https://github.com/LiveSplit/livesplit-core", rev = "61070c47ea91e6e148d6801cb7a03e8e32a2ebc9", default-features = false, features = ["std", "localization", "image-shrinking", "software-rendering", "font-loading"] }
livesplit-core-capi = { git = "https://github.com/LiveSplit/livesplit-core", rev = "61070c47ea91e6e148d6801cb7a03e8e32a2ebc9", default-features = false, features = ["default-api", "localization", "image-shrinking", "software-rendering"] }
futures-executor = "0.3.34"
```

`core/src/lib.rs` (the other modules come in Steps 5 and 9):

```rust
//! lso-core: livesplit-core's C API plus the functions a native app needs that
//! the C API only offers on the web (spec §5.3).

pub mod sink;
```

`core/src/sink.rs`, the tests first:

```rust
//! The event-reporting command sink (spec §5.3).

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use livesplit_core::{Run, Segment, event::Event};
    use std::sync::{Arc, Mutex, mpsc};

    pub(crate) fn timer(segments: &[&str]) -> SharedTimer {
        let mut run = Run::new();
        for name in segments {
            run.push_segment(Segment::new(*name));
        }
        Timer::new(run).unwrap().into_shared()
    }

    #[derive(Default)]
    pub(crate) struct Recorder {
        pub results: Mutex<Vec<Result>>,
        pub decision: Mutex<Option<ResetDecision>>,
        pub asked: Mutex<u32>,
    }

    impl Host for Arc<Recorder> {
        fn report(&self, result: Result) {
            self.results.lock().unwrap().push(result);
        }
        fn decide_reset(&self) -> ResetDecision {
            *self.asked.lock().unwrap() += 1;
            self.decision
                .lock()
                .unwrap()
                .expect("unexpected reset question")
        }
    }

    fn sink(segments: &[&str]) -> (EventSink<Arc<Recorder>>, Arc<Recorder>) {
        let recorder = Arc::new(Recorder::default());
        (EventSink::new(timer(segments), recorder.clone()), recorder)
    }

    fn run<F: Future<Output = Result>>(future: F) -> Result {
        futures_executor::block_on(future)
    }

    #[test]
    fn applies_a_command_and_reports_its_event() {
        let (sink, recorder) = sink(&["One"]);
        assert_eq!(run(sink.start()), Ok(Event::Started));
        assert_eq!(*recorder.results.lock().unwrap(), [Ok(Event::Started)]);
        assert_eq!(
            sink.get_timer().current_phase(),
            livesplit_core::TimerPhase::Running
        );
    }

    #[test]
    fn reports_errors_too() {
        let (sink, recorder) = sink(&["One"]);
        assert_eq!(run(sink.split()), Err(Error::NoRunInProgress));
        assert_eq!(
            *recorder.results.lock().unwrap(),
            [Err(Error::NoRunInProgress)]
        );
    }

    #[test]
    fn reset_without_new_best_times_does_not_ask() {
        let (sink, recorder) = sink(&["One", "Two"]);
        run(sink.start()).unwrap();
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 0);
    }

    fn with_new_best_segment(sink: &EventSink<Arc<Recorder>>) {
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();
        assert!(sink.get_timer().current_attempt_has_new_best_times());
    }

    #[test]
    fn reset_with_new_best_times_asks_and_saves() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Save);
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 1);
        assert_eq!(sink.get_timer().run().attempt_history().len(), 1);
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_some()
        );
    }

    #[test]
    fn reset_with_new_best_times_can_discard() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Discard);
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_none()
        );
    }

    #[test]
    fn reset_can_be_cancelled() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Cancel);
        assert_eq!(run(sink.reset(None)), Err(Error::RunnerDecidedAgainstReset));
        assert_eq!(
            sink.get_timer().current_phase(),
            livesplit_core::TimerPhase::Running
        );
        assert_eq!(
            recorder.results.lock().unwrap().last(),
            Some(&Err(Error::RunnerDecidedAgainstReset))
        );
    }

    #[test]
    fn reset_that_says_whether_to_save_does_not_ask() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        assert_eq!(run(sink.reset(Some(false))), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 0);
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_none()
        );
    }

    /// A host whose reset question waits until the test lets it answer.
    struct Waiting {
        asked: mpsc::Sender<()>,
        answer: Mutex<mpsc::Receiver<ResetDecision>>,
    }

    impl Host for Waiting {
        fn report(&self, _: Result) {}
        fn decide_reset(&self) -> ResetDecision {
            self.asked.send(()).unwrap();
            self.answer.lock().unwrap().recv().unwrap()
        }
    }

    #[test]
    fn other_commands_are_busy_while_a_reset_waits_and_the_timer_is_not_locked() {
        let (asked_tx, asked_rx) = mpsc::channel();
        let (answer_tx, answer_rx) = mpsc::channel();
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two"]),
            Waiting {
                asked: asked_tx,
                answer: Mutex::new(answer_rx),
            },
        ));
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();

        let resetting = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.reset(None)))
        };
        asked_rx.recv().unwrap();

        assert_eq!(run(sink.split()), Err(Error::Busy));
        assert_eq!(run(sink.reset(None)), Err(Error::Busy));
        // Drawing still gets the read lock while the question is open.
        assert_eq!(sink.get_timer().current_split_index(), Some(1));

        answer_tx.send(ResetDecision::Save).unwrap();
        assert_eq!(resetting.join().unwrap(), Ok(Event::Reset));
        assert_eq!(run(sink.start()), Ok(Event::Started));
    }
}
```

Add to `.gitignore`: `/core/target/`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test --manifest-path core/Cargo.toml`
Expected: Cargo fetches livesplit-core (the first build takes a few minutes, and creates `core/Cargo.lock`), then compile errors such as `cannot find type 'EventSink'`, `cannot find trait 'Host'`, `cannot find type 'ResetDecision'` and `cannot find type 'SharedTimer'`.

- [ ] **Step 3: Implement the sink**

In `core/src/sink.rs`, add below the module doc comment, above `#[cfg(test)]`:

```rust
use std::{
    borrow::Cow,
    future::{Future, ready},
    pin::pin,
    sync::{
        RwLockReadGuard,
        atomic::{AtomicBool, Ordering},
    },
    task::{Context, Poll, Waker},
};

use livesplit_core::{
    SharedTimer, TimeSpan, Timer, TimingMethod,
    event::{CommandSink, Error, Result, TimerQuery},
};

/// What the host decided when a reset needs a decision. The values match the
/// buttons of LiveSplit One's dialog: Yes, No, Don't Reset.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum ResetDecision {
    /// Keep the attempt's times (Yes).
    Save,
    /// Discard the attempt's times (No).
    Discard,
    /// Don't reset.
    Cancel,
}

/// The app side of the sink: told about every result, and asked about resets.
pub trait Host: Send + Sync + 'static {
    /// Called after every command with the event it caused or its error.
    fn report(&self, result: Result);
    /// Called when a reset doesn't say whether to keep the attempt's times and
    /// the attempt has new best times. Blocks the calling thread until the
    /// user answers. The timer is not locked while it waits.
    fn decide_reset(&self) -> ResetDecision;
}

/// Wraps the shared timer, applies every command to it and reports the result
/// to the host, as LiveSplit One's `LSOCommandSink` does.
pub struct EventSink<H: Host> {
    timer: SharedTimer,
    host: H,
    deciding: AtomicBool,
}

impl<H: Host> EventSink<H> {
    /// Creates a sink for a handle to the shared timer.
    pub fn new(timer: SharedTimer, host: H) -> Self {
        Self {
            timer,
            host,
            deciding: AtomicBool::new(false),
        }
    }

    /// Runs a command against the shared timer, unless a reset decision is
    /// pending, and reports the result.
    fn apply(&self, command: impl FnOnce(&SharedTimer) -> Result) -> Result {
        let result = if self.deciding.load(Ordering::Acquire) {
            Err(Error::Busy)
        } else {
            command(&self.timer)
        };
        self.host.report(result);
        result
    }

    fn reset_decision(&self) -> core::result::Result<bool, Error> {
        if self.deciding.swap(true, Ordering::AcqRel) {
            return Err(Error::Busy);
        }
        // Clears the flag even if the host panics.
        struct Clear<'a>(&'a AtomicBool);
        impl Drop for Clear<'_> {
            fn drop(&mut self) {
                self.0.store(false, Ordering::Release);
            }
        }
        let _clear = Clear(&self.deciding);

        let has_new_best_times = self
            .timer
            .read()
            .unwrap()
            .current_attempt_has_new_best_times();
        if !has_new_best_times {
            return Ok(true);
        }
        match self.host.decide_reset() {
            ResetDecision::Save => Ok(true),
            ResetDecision::Discard => Ok(false),
            ResetDecision::Cancel => Err(Error::RunnerDecidedAgainstReset),
        }
    }
}

/// Takes the result of one of `SharedTimer`'s command futures. They apply the
/// command when created and are ready at once (livesplit-core `src/event.rs`,
/// `impl CommandSink for SharedTimer`), so one poll is enough. This doesn't use
/// an executor, because `handle_command` already runs inside one, and
/// `futures_executor::block_on` panics when nested.
fn now(future: impl Future<Output = Result>) -> Result {
    let mut context = Context::from_waker(Waker::noop());
    match pin!(future).poll(&mut context) {
        Poll::Ready(result) => result,
        Poll::Pending => Err(Error::Unknown),
    }
}

impl<H: Host> CommandSink for EventSink<H> {
    fn start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::start(t))))
    }
    fn split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::split(t))))
    }
    fn split_or_start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::split_or_start(t))))
    }
    fn reset(&self, save_attempt: Option<bool>) -> impl Future<Output = Result> + 'static {
        let result = match save_attempt {
            Some(save) => self.apply(|t| now(CommandSink::reset(t, Some(save)))),
            None => match self.reset_decision() {
                Ok(save) => self.apply(|t| now(CommandSink::reset(t, Some(save)))),
                Err(error) => {
                    self.host.report(Err(error));
                    Err(error)
                }
            },
        };
        ready(result)
    }
    fn undo_split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::undo_split(t))))
    }
    fn skip_split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::skip_split(t))))
    }
    fn toggle_pause_or_start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::toggle_pause_or_start(t))))
    }
    fn pause(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::pause(t))))
    }
    fn resume(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::resume(t))))
    }
    fn undo_all_pauses(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::undo_all_pauses(t))))
    }
    fn switch_to_previous_comparison(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::switch_to_previous_comparison(t))))
    }
    fn switch_to_next_comparison(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::switch_to_next_comparison(t))))
    }
    fn set_current_comparison(
        &self,
        comparison: Cow<str>,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_current_comparison(t, comparison))))
    }
    fn toggle_timing_method(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::toggle_timing_method(t))))
    }
    fn set_current_timing_method(
        &self,
        method: TimingMethod,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_current_timing_method(t, method))))
    }
    fn initialize_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::initialize_game_time(t))))
    }
    fn set_game_time(&self, time: TimeSpan) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_game_time(t, time))))
    }
    fn pause_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::pause_game_time(t))))
    }
    fn resume_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::resume_game_time(t))))
    }
    fn set_loading_times(&self, time: TimeSpan) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_loading_times(t, time))))
    }
    fn set_custom_variable(
        &self,
        name: Cow<str>,
        value: Cow<str>,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_custom_variable(t, name, value))))
    }
}

impl<H: Host> TimerQuery for EventSink<H> {
    type Guard<'a> = RwLockReadGuard<'a, Timer>;
    fn get_timer(&self) -> Self::Guard<'_> {
        self.timer.read().unwrap()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cargo test --locked --manifest-path core/Cargo.toml`
Expected: 8 tests pass.

- [ ] **Step 5: Write the failing protocol tests**

Add `pub mod protocol;` to `core/src/lib.rs`, above `pub mod sink;`.

`core/src/protocol.rs`:

```rust
//! LiveSplit One's server protocol on native (spec §5.3). livesplit-core's C
//! API only exposes it on the web (`capi/src/lib.rs`, `server_protocol`).

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sink::{
        ResetDecision,
        tests::{Recorder, timer},
    };
    use std::sync::Arc;

    fn sink() -> (EventSink<Arc<Recorder>>, Arc<Recorder>) {
        let recorder = Arc::new(Recorder::default());
        (
            EventSink::new(timer(&["One", "Two"]), recorder.clone()),
            recorder,
        )
    }

    #[test]
    fn a_command_succeeds_and_reports_its_event() {
        let (sink, recorder) = sink();
        assert_eq!(
            handle_command(&sink, r#"{"command":"splitOrStart"}"#),
            r#"{"success":null}"#
        );
        assert_eq!(*recorder.results.lock().unwrap(), [Ok(Event::Started)]);
    }

    #[test]
    fn a_rejected_command_replies_with_the_timer_error() {
        let (sink, _) = sink();
        assert_eq!(
            handle_command(&sink, r#"{"command":"split"}"#),
            r#"{"error":{"code":"NoRunInProgress"}}"#
        );
    }

    #[test]
    fn invalid_json_replies_invalid_command() {
        let (sink, recorder) = sink();
        let reply = handle_command(&sink, "not json");
        assert!(
            reply.starts_with(r#"{"error":{"code":"InvalidCommand","message":"#),
            "{reply}"
        );
        assert!(recorder.results.lock().unwrap().is_empty());
    }

    #[test]
    fn queries_read_the_timer() {
        let (sink, _) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        assert_eq!(
            handle_command(&sink, r#"{"command":"getCurrentState"}"#),
            r#"{"success":{"state":"Running","index":0}}"#
        );
    }

    #[test]
    fn game_time_commands_work() {
        let (sink, recorder) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        handle_command(&sink, r#"{"command":"initializeGameTime"}"#);
        assert_eq!(
            handle_command(&sink, r#"{"command":"setGameTime","time":"1:23.5"}"#),
            r#"{"success":null}"#
        );
        assert_eq!(
            recorder.results.lock().unwrap().last(),
            Some(&Ok(Event::GameTimeSet))
        );
    }

    #[test]
    fn a_server_reset_waits_for_the_decision_and_replies_with_it() {
        let (sink, recorder) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        std::thread::sleep(std::time::Duration::from_millis(2));
        handle_command(&sink, r#"{"command":"split"}"#);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Cancel);
        assert_eq!(
            handle_command(&sink, r#"{"command":"reset"}"#),
            r#"{"error":{"code":"RunnerDecidedAgainstReset"}}"#
        );
        assert_eq!(
            handle_command(&sink, r#"{"command":"reset","saveAttempt":false}"#),
            r#"{"success":null}"#
        );
        assert_eq!(*recorder.asked.lock().unwrap(), 1);
    }

    #[test]
    fn encodes_events_as_livesplit_one_does() {
        assert_eq!(
            encode_event(Event::Splitted as u32),
            r#"{"event":"Splitted"}"#
        );
        assert_eq!(encode_event(Event::Reset as u32), r#"{"event":"Reset"}"#);
        assert_eq!(encode_event(9999), r#"{"event":"Unknown"}"#);
    }
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cargo test --locked --manifest-path core/Cargo.toml`
Expected: compile errors `cannot find function 'handle_command'` and `cannot find function 'encode_event'`.

- [ ] **Step 7: Implement the protocol functions**

In `core/src/protocol.rs`, add below the module doc comment:

```rust
use livesplit_core::{event::Event, networking::server_protocol};

use crate::sink::{EventSink, Host};

/// Runs one server protocol message against the sink and returns the reply to
/// send back. The sink's futures are ready at once, so this never waits,
/// except for a reset decision (see [`Host::decide_reset`]).
pub fn handle_command<H: Host>(sink: &EventSink<H>, command: &str) -> String {
    futures_executor::block_on(server_protocol::handle_command(command, sink))
}

/// Encodes an event, given as livesplit-core's number for it, as LiveSplit One
/// sends it to the server. Unknown numbers encode as `"Unknown"`, as in
/// LiveSplit One (`capi/src/server_protocol.rs`).
pub fn encode_event(event: u32) -> String {
    server_protocol::encode_event(Event::from(event))
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cargo test --locked --manifest-path core/Cargo.toml`
Expected: 15 tests pass.

- [ ] **Step 9: Write the failing C function tests**

Make `core/src/lib.rs`:

```rust
//! lso-core: livesplit-core's C API plus the functions a native app needs that
//! the C API only offers on the web (spec §5.3).

pub mod ffi;
pub mod protocol;
pub mod sink;
```

`core/src/ffi.rs`:

```rust
//! The C functions Swift calls, declared in
//! `LiveSplitCore/CLiveSplitCore/include/lso_core.h`. Names
//! follow livesplit-core's C API: `Type_method`.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sink::tests::timer;
    use livesplit_core::event::{Error, Event};
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct Calls {
        results: Mutex<Vec<i32>>,
        released: Mutex<bool>,
    }

    extern "C" fn report(context: *mut c_void, result: i32) {
        // SAFETY: the tests pass an `Arc<Calls>` pointer as the context.
        let calls = unsafe { &*(context as *const Calls) };
        calls.results.lock().unwrap().push(result);
    }
    extern "C" fn decide_reset(_: *mut c_void) -> u8 {
        2
    }
    extern "C" fn release(context: *mut c_void) {
        // SAFETY: as above; this takes back the reference given to the host.
        let calls = unsafe { Arc::from_raw(context as *const Calls) };
        *calls.released.lock().unwrap() = true;
    }

    fn host(calls: &Arc<Calls>) -> LsoHost {
        LsoHost {
            context: Arc::into_raw(calls.clone()) as *mut c_void,
            report,
            decide_reset,
            release,
        }
    }

    fn string(ptr: *const c_char) -> String {
        // SAFETY: the functions under test return valid strings.
        unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_owned()
    }

    #[test]
    fn encodes_results_like_the_c_api() {
        assert_eq!(encode_result(Ok(Event::Started)), 0);
        assert_eq!(encode_result(Ok(Event::Splitted)), 1);
        assert_eq!(encode_result(Err(Error::Unsupported)), -1);
        assert_eq!(encode_result(Err(Error::Busy)), -2);
    }

    #[test]
    fn runs_a_command_through_the_c_functions() {
        let calls = Arc::new(Calls::default());
        let shared = timer(&["One"]);
        let sink = LsoCommandSink_new(&shared, host(&calls));
        drop(shared); // The sink keeps the timer alive.

        let command = CString::new(r#"{"command":"start"}"#).unwrap();
        // SAFETY: a valid string.
        let reply = string(unsafe { LsoCommandSink_handle_command(&sink, command.as_ptr()) });
        assert_eq!(reply, r#"{"success":null}"#);
        assert_eq!(*calls.results.lock().unwrap(), [Event::Started as i32]);

        LsoCommandSink_drop(sink);
        assert!(*calls.released.lock().unwrap());
    }

    #[test]
    fn invalid_utf8_and_null_get_invalid_command() {
        let calls = Arc::new(Calls::default());
        let sink = LsoCommandSink_new(&timer(&["One"]), host(&calls));
        let bad = [0xffu8, 0xfe, 0];
        // SAFETY: nul-terminated bytes, and null.
        let replies = unsafe {
            [
                string(LsoCommandSink_handle_command(
                    &sink,
                    bad.as_ptr() as *const c_char,
                )),
                string(LsoCommandSink_handle_command(&sink, std::ptr::null())),
            ]
        };
        for reply in replies {
            assert!(reply.contains(r#""code":"InvalidCommand""#), "{reply}");
        }
    }

    #[test]
    fn encodes_an_event_through_the_c_function() {
        assert_eq!(
            string(LsoServerProtocol_encode_event(0)),
            r#"{"event":"Started"}"#
        );
    }
}
```

- [ ] **Step 10: Run the tests to verify they fail**

Run: `cargo test --locked --manifest-path core/Cargo.toml`
Expected: compile errors such as `cannot find type 'LsoHost'` and `cannot find function 'LsoCommandSink_new'`.

- [ ] **Step 11: Implement the C functions and their header**

In `core/src/ffi.rs`, add below the module doc comment:

```rust
use std::{
    cell::RefCell,
    ffi::{CStr, CString, c_char, c_void},
};

use livesplit_core::{SharedTimer, event::Result};

use crate::{
    protocol,
    sink::{EventSink, Host, ResetDecision},
};

/// The app's callbacks. `context` is passed back to every callback, and
/// `release` is called once when the sink is dropped. The callbacks may be
/// called from any thread that runs a command.
#[repr(C)]
pub struct LsoHost {
    pub context: *mut c_void,
    /// Gets each command's result, encoded as livesplit-core's C API encodes
    /// it (`capi/src/timer.rs`, `convert`): an event is its number (0 or
    /// more), an error `e` is `-1 - e`.
    pub report: extern "C" fn(context: *mut c_void, result: i32),
    /// Asks whether to keep the attempt's times: 0 keep, 1 discard, anything
    /// else don't reset.
    pub decide_reset: extern "C" fn(context: *mut c_void) -> u8,
    pub release: extern "C" fn(context: *mut c_void),
}

// SAFETY: the app promises its callbacks can be called from any thread.
unsafe impl Send for LsoHost {}
// SAFETY: as above.
unsafe impl Sync for LsoHost {}

impl Drop for LsoHost {
    fn drop(&mut self) {
        (self.release)(self.context);
    }
}

/// Encodes a result as livesplit-core's C API does.
pub fn encode_result(result: Result) -> i32 {
    match result {
        Ok(event) => event as i32,
        Err(error) => -1 - (error as i32),
    }
}

impl Host for LsoHost {
    fn report(&self, result: Result) {
        (self.report)(self.context, encode_result(result));
    }

    fn decide_reset(&self) -> ResetDecision {
        match (self.decide_reset)(self.context) {
            0 => ResetDecision::Save,
            1 => ResetDecision::Discard,
            _ => ResetDecision::Cancel,
        }
    }
}

/// The sink as Swift sees it.
pub type LsoCommandSink = EventSink<LsoHost>;

thread_local! {
    static OUTPUT: RefCell<CString> = RefCell::new(CString::default());
}

/// Returns a string that stays valid until the next call on the same thread,
/// as livesplit-core's C API does with its own strings.
fn output(s: String) -> *const c_char {
    OUTPUT.with_borrow_mut(|out| {
        *out = CString::new(s).unwrap_or_default();
        out.as_ptr()
    })
}

/// Creates a sink for the shared timer. The sink keeps its own handle to the
/// timer, so the caller may drop theirs.
#[unsafe(no_mangle)]
pub extern "C" fn LsoCommandSink_new(timer: &SharedTimer, host: LsoHost) -> Box<LsoCommandSink> {
    Box::new(EventSink::new(timer.clone(), host))
}

/// Drops the sink and releases the host's context.
#[unsafe(no_mangle)]
pub extern "C" fn LsoCommandSink_drop(this: Box<LsoCommandSink>) {
    drop(this);
}

/// Runs one server protocol message (UTF-8 JSON) and returns the reply.
/// Invalid UTF-8 is replaced, so it gets an `InvalidCommand` reply instead of
/// stopping the app. A null `command` is treated as empty.
///
/// # Safety
/// `command` is null or a valid nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn LsoCommandSink_handle_command(
    this: &LsoCommandSink,
    command: *const c_char,
) -> *const c_char {
    let command = if command.is_null() {
        Default::default()
    } else {
        // SAFETY: the caller passes a valid nul-terminated string.
        String::from_utf8_lossy(unsafe { CStr::from_ptr(command) }.to_bytes())
    };
    output(protocol::handle_command(this, &command))
}

/// Encodes an event (livesplit-core's number for it) for the server.
#[unsafe(no_mangle)]
pub extern "C" fn LsoServerProtocol_encode_event(event: u32) -> *const c_char {
    output(protocol::encode_event(event))
}
```

`LiveSplitCore/CLiveSplitCore/include/lso_core.h`, which Task 3's module map includes:

```c
// The functions core/ adds to livesplit-core's C API (spec §5.3).
// Implemented in core/src/ffi.rs. Keep the two in sync.
#ifndef LSO_CORE_H
#define LSO_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The app's callbacks for a command sink. `context` is passed to each one;
/// `release` is called once when the sink is dropped. Callbacks may run on any
/// thread that runs a command.
typedef struct LsoHost {
    void *context;
    /// Each command's result: an event number (0 or more), or `-1 - error`.
    void (*report)(void *context, int32_t result);
    /// 0 keeps the attempt's times, 1 discards them, anything else doesn't reset.
    uint8_t (*decide_reset)(void *context);
    void (*release)(void *context);
} LsoHost;

/// Creates a command sink for a `SharedTimer`. The sink keeps its own handle.
void *LsoCommandSink_new(void *timer, LsoHost host);
void LsoCommandSink_drop(void *self);
/// Runs one server protocol message. The reply stays valid until the next call
/// on the same thread.
char const *LsoCommandSink_handle_command(void *self, char const *command);
/// Encodes an event for the server. Valid until the next call on the thread.
char const *LsoServerProtocol_encode_event(uint32_t event);

#ifdef __cplusplus
}
#endif

#endif
```

- [ ] **Step 12: Run all Rust checks**

```bash
cargo fmt --check --manifest-path core/Cargo.toml
cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
cargo test --locked --manifest-path core/Cargo.toml
```

Expected: no formatting differences, no clippy warnings, 19 tests pass.

- [ ] **Step 13: Check both static libraries are built**

```bash
cargo build --locked --manifest-path core/Cargo.toml --message-format=json-render-diagnostics \
  | jq -r 'select(.reason == "compiler-artifact" and (.target.kind | index("staticlib")))
      | "\(.target.name) \(.filenames[] | select(endswith(".a")))"'
nm -gU core/target/debug/liblso_core.a 2>/dev/null | grep -c ' _Lso'
```

Expected: two lines, `livesplit_core …/core/target/debug/deps/liblivesplit_core-<hash>.a` and `lso_core …/core/target/debug/liblso_core.a`; then `4` (the four `Lso…` functions). The C API's library has a hash in its name because its library name collides with livesplit-core's, which is why Task 3 finds it through Cargo's messages, never by path.

- [ ] **Step 14: Commit and open the pull request**

```bash
git add core/Cargo.toml core/Cargo.lock core/src LiveSplitCore/CLiveSplitCore/include/lso_core.h .gitignore
git commit -m "feat(core): add the core crate with the server protocol functions"
git push -u origin feat/core-crate
gh pr create --base main --title "feat(core): add the core crate with the server protocol functions" --body-file "$PR_BODY"
```

Stop here. The maintainer merges.

---

### Task 3: Build core and the Swift bindings into the app (issue #6, second part)

**Branch:** `feat/livesplitcore-bindings` · **PR title:** `feat: build core and the Swift bindings into the app` · **PR body:** `Closes #6`, using the pull request template.

**Files:**
- Create: `scripts/build-core.sh` (builds core and regenerates the bindings)
- Create: `LiveSplitCore/CLiveSplitCore/include/module.modulemap` (the C module, hand-written)
- Create: `LiveSplitCore/CLiveSplitCore/include/CLiveSplitCore.h` (its umbrella header)
- Create: `LiveSplitCore/Wrapper/EventSink.swift` (Swift for core's additions)
- Create: `Tests/Integration/EventSinkTests.swift`
- Modify: `project.yml` (the `LiveSplitCore` target and its build phase)
- Modify: `.gitignore`, `CONTRIBUTING.md`, spec §4 and §4.1

**Interfaces:**
- Consumes: Task 2's C functions and `lso_core.h`; Task 1's targets.
- Produces:
  - `scripts/build-core.sh [--release] [--universal] [--bindings-only]`; in an Xcode build phase it reads `CONFIGURATION`, `ARCHS` and `DERIVED_FILE_DIR` instead. Outputs: `LiveSplitCore/lib/liblivesplit_core.a`, `LiveSplitCore/lib/liblso_core.a` (universal when two architectures are built), `LiveSplitCore/Generated/LiveSplitCore.swift`, `LiveSplitCore/CLiveSplitCore/include/livesplit_core.h`, and `$DERIVED_FILE_DIR/build-core.d`.
  - Xcode target `LiveSplitCore` (static library, module `LiveSplitCore`) with every generated class (`Run`, `Segment`, `Timer`, `SharedTimer`, `Layout`, `SoftwareRenderer`, …) and: `EventSink(timer: SharedTimerRef, report: @Sendable (CommandResult) -> Void, decideReset: @Sendable () -> ResetDecision)`, `EventSink.handleCommand(_: String) -> String`, `EventSink.encodeEvent(_: TimerEvent) -> String` (static), `enum TimerEvent: UInt32`, `enum TimerError: UInt32, Error`, `enum CommandResult { case event(TimerEvent?), error(TimerError?) }`, `enum ResetDecision: UInt8 { save, discard, cancel }`.
  - Contract for later issues: `report` and `decideReset` run on the thread that ran the command, and `decideReset` blocks that thread until it returns. Server commands run on a background queue (spec §8.2); a command from the main thread must not lead to `decideReset` blocking the main thread while it waits for an alert on the main thread.

Key facts, verified with livesplit-core `61070c47` and Swift 6.2.1:
- **bind_gen** is the `bindings` binary in `capi/bind_gen` (`capi/bind_gen/Cargo.toml`). It reads `../src/lib.rs` and `../src/<module>.rs` relative to the current directory (`capi/bind_gen/src/main.rs:226-240`), so it must run from `capi/bind_gen`. Its flags are `--features <a,b>` (comma-separated), `--no-default-features` and `--output-dir <dir>` (`main.rs:40-50`). It deletes the output directory first (`main.rs`, `write_files`, `remove_dir_all`), so it writes to a temporary one. It resolves features from capi's `Cargo.toml` with `cargo metadata --no-deps` (`main.rs:336-391`), and treats target predicates such as `target_family = "wasm"` as enabled while still applying feature predicates (`main.rs:394-400`). LiveSplit One's web build runs it the same way (`LiveSplitOne/buildCore.ts`: `cargo run -- --no-default-features --features … --output-dir …` in `livesplit-core/capi/bind_gen`).
- **Its Swift output** (`capi/bind_gen/src/swift/mod.rs`) is `swift/LiveSplitCore/LiveSplitCore.swift` and `swift/CLiveSplitCore/` with `include/livesplit_core.h`, `include/module.modulemap` (`link "livesplit_core"`, frameworks Carbon, CoreFoundation, CoreGraphics) and an empty `livesplit_core.c` for SwiftPM. The script copies only the Swift file and the header.
- **The generated header doesn't build as a module on the current SDK:** `livesplit_core.h` uses `ssize_t` (`Timer_current_split_index`) but only includes `<stdint.h>`, `<stddef.h>` and `<stdbool.h>`, and the macOS 26 SDK's modules fail with `declaration of 'ssize_t' must be imported from module '_DarwinFoundation2.sys_types.ssize_t'`. The hand-written umbrella header includes `<sys/types.h>` first. Worth reporting upstream.
- **The generated classes' `ptr` is internal** (`var ptr: UnsafeMutableRawPointer?`), so the wrapper must be in the same Swift module as the generated file to pass a `SharedTimer` to `LsoCommandSink_new`. The generated code already has a class named `CommandSink` (the C API's, which wraps a plain timer and reports nothing), so the wrapper is `EventSink`. The generated file builds in Swift 6 language mode.
- **Upstream has no `Cargo.lock`** (livesplit-core's `.gitignore` lists it), so bind_gen's own dependencies (clap, syn, heck, serde_json) resolve at their newest compatible versions the first time it builds, and Cargo writes a `Cargo.lock` into its checkout under `~/.cargo/git/checkouts/`. bind_gen doesn't ship, so this only affects the build tool; the script runs it only when the revision or features change.
- **Why not a Swift package:** Xcode builds a project's Swift package dependencies before running any of the project's build phases, so a package couldn't be regenerated by the phase spec §4.2 asks for. A static library target with its own pre-build script runs the script before compiling its Swift.
- **Skipping the phase:** the script writes a Makefile-style dependency file (`discoveredDependencyFile`) listing cargo's own dependency file for `liblso_core.a` (every `.rs` it compiled) plus `core/Cargo.toml`, `core/Cargo.lock`, `rust-toolchain.toml` and the script itself. Xcode's script sandbox must be off for that target, because the script writes into the repository and `~/.cargo`.

- [ ] **Step 1: Write the C module**

`LiveSplitCore/CLiveSplitCore/include/module.modulemap`:

```
// Hand-written, not bind_gen's: it adds core/'s header and library, and an
// umbrella header that includes <sys/types.h> first, because the generated
// livesplit_core.h uses ssize_t without including it.
module CLiveSplitCore [extern_c] {
    header "CLiveSplitCore.h"
    link "livesplit_core"
    link "lso_core"
    link framework "Carbon"
    link framework "CoreFoundation"
    link framework "CoreGraphics"
    export *
}
```

`LiveSplitCore/CLiveSplitCore/include/CLiveSplitCore.h`:

```c
// Umbrella header for the CLiveSplitCore module. See module.modulemap.
#include <sys/types.h>
#include "livesplit_core.h"
#include "lso_core.h"
```

Add to `.gitignore`:

```
/LiveSplitCore/lib/
/LiveSplitCore/Generated/
/LiveSplitCore/CLiveSplitCore/include/livesplit_core.h
```

- [ ] **Step 2: Write `scripts/build-core.sh`**

```bash
#!/usr/bin/env bash
# Builds core/ and regenerates the Swift bindings into LiveSplitCore/ (spec
# §4.2).
#
#   scripts/build-core.sh                        debug, this Mac's architecture
#   scripts/build-core.sh --release              release, this Mac's architecture
#   scripts/build-core.sh --release --universal  release, Apple Silicon and Intel
#   scripts/build-core.sh --bindings-only        only the Swift bindings, for
#                                                xcodegen's preGenCommand
#
# In Xcode's build phase, CONFIGURATION and ARCHS choose instead, and the
# script writes a dependency file so Xcode skips the phase when nothing it
# read has changed.
set -euo pipefail

# Xcode's build phases don't see the login shell's PATH.
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/core/Cargo.toml"
out="$root/LiveSplitCore"

release=false
bindings_only=false
archs=$(uname -m)
for arg in "$@"; do
  case "$arg" in
    --release) release=true ;;
    --universal) archs="arm64 x86_64" ;;
    --bindings-only) bindings_only=true ;;
    *)
      echo "usage: build-core.sh [--release] [--universal] [--bindings-only]" >&2
      exit 2
      ;;
  esac
done
if [[ -n "${CONFIGURATION:-}" ]]; then
  if [[ "$CONFIGURATION" == Release ]]; then release=true; else release=false; fi
  archs=${ARCHS:-$archs}
fi
profile=debug
if $release; then profile=release; fi

rust_target() {
  case "$1" in
    arm64) echo aarch64-apple-darwin ;;
    x86_64) echo x86_64-apple-darwin ;;
    *)
      echo "unsupported architecture: $1" >&2
      exit 1
      ;;
  esac
}

metadata=$(cargo metadata --format-version 1 --locked --manifest-path "$manifest")
# The C API's features are read from core/Cargo.toml, so the bindings always
# describe the library that is built.
features=$(jq -r '.packages[] | select(.name == "lso-core") | .dependencies[]
  | select(.name == "livesplit-core-capi") | .features | join(",")' <<<"$metadata")
capi_dir=$(jq -r '.packages[] | select(.name == "livesplit-core-capi")
  | .manifest_path | rtrimstr("/Cargo.toml")' <<<"$metadata")

# Builds one target. Prints "<crate> <path>" for its two static libraries:
# livesplit_core (the C API) and lso_core (core/).
build_target() {
  local target=$1 release_flag=""
  if $release; then release_flag=--release; fi
  # shellcheck disable=SC2086 # release_flag is empty or one word
  cargo build --locked --manifest-path "$manifest" --target "$target" $release_flag \
    --message-format=json-render-diagnostics |
    jq -r 'select(.reason == "compiler-artifact" and (.target.kind | index("staticlib")))
      | [.target.name, (.filenames[] | select(endswith(".a")))] | @tsv'
}

build_libraries() {
  local arch target name path capi_libs=() core_libs=()
  for arch in $archs; do
    target=$(rust_target "$arch")
    while IFS=$'\t' read -r name path; do
      case "$name" in
        livesplit_core) capi_libs+=("$path") ;;
        lso_core) core_libs+=("$path") ;;
      esac
    done < <(build_target "$target")
  done
  local count
  count=$(wc -w <<<"$archs")
  if ((${#capi_libs[@]} != count || ${#core_libs[@]} != count)); then
    echo "cargo didn't report both static libraries for: $archs" >&2
    exit 1
  fi
  mkdir -p "$out/lib"
  lipo -create "${capi_libs[@]}" -output "$out/lib/liblivesplit_core.a"
  lipo -create "${core_libs[@]}" -output "$out/lib/liblso_core.a"
}

# The bindings only change with the livesplit-core revision or the features,
# so bind_gen only runs when one of them changed.
generate_bindings() {
  local stamp="$out/Generated/.source"
  local source_id="$capi_dir $features"
  local swift_out="$out/Generated/LiveSplitCore.swift"
  local header_out="$out/CLiveSplitCore/include/livesplit_core.h"
  if [[ -f "$swift_out" && -f "$header_out" && "$(cat "$stamp" 2>/dev/null)" == "$source_id" ]]; then
    return
  fi
  local bindings
  bindings=$(mktemp -d)
  # bind_gen reads ../src relative to its own folder, so it runs from there,
  # and builds into core/target instead of Cargo's checkout.
  (cd "$capi_dir/bind_gen" &&
    cargo run --release --quiet --target-dir "$root/core/target/bind_gen" -- \
      --no-default-features --features "$features" --output-dir "$bindings")
  mkdir -p "$out/Generated"
  cp "$bindings/swift/LiveSplitCore/LiveSplitCore.swift" "$swift_out"
  cp "$bindings/swift/CLiveSplitCore/include/livesplit_core.h" "$header_out"
  echo "$source_id" >"$stamp"
  rm -rf "$bindings"
}

# Tells Xcode what this run read, so it skips the phase until one of them
# changes (spec §4.2): core/'s Rust sources (cargo's dependency file), its
# manifest and lock file, the toolchain file and this script.
write_xcode_dependencies() {
  local first depinfo inputs
  first=$(rust_target "${archs%% *}")
  depinfo="$root/core/target/$first/$profile/liblso_core.d"
  inputs=$(cut -d: -f2- "$depinfo")
  mkdir -p "$DERIVED_FILE_DIR"
  echo "$out/lib/liblso_core.a: $inputs $root/core/Cargo.toml $root/core/Cargo.lock" \
    "$root/rust-toolchain.toml $root/scripts/build-core.sh" >"$DERIVED_FILE_DIR/build-core.d"
}

generate_bindings
if $bindings_only; then
  exit 0
fi
build_libraries
if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
  write_xcode_dependencies
fi
```

Run: `chmod +x scripts/build-core.sh && mise x -- shellcheck scripts/build-core.sh`
Expected: no output.

- [ ] **Step 3: Run the script**

```bash
scripts/build-core.sh --bindings-only
ls LiveSplitCore/Generated LiveSplitCore/CLiveSplitCore/include
scripts/build-core.sh
lipo -info LiveSplitCore/lib/*.a
```

Expected: `LiveSplitCore.swift` in `Generated/`; `CLiveSplitCore.h`, `livesplit_core.h`, `lso_core.h` and `module.modulemap` in `include/`; both libraries listed as `arm64` (or `x86_64` on an Intel Mac). A second `scripts/build-core.sh --bindings-only` returns in about a second, since bind_gen doesn't run again.

- [ ] **Step 4: Write the failing integration tests**

`Tests/Integration/EventSinkTests.swift`:

```swift
import Foundation
import LiveSplitCore
import Testing

/// Collects results from whatever thread the sink reports on.
private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CommandResult] = []

    func append(_ value: CommandResult) { lock.withLock { values.append(value) } }
    var all: [CommandResult] { lock.withLock { values } }
}

/// A timer with one segment, so it can start.
private func makeTimer() -> SharedTimer {
    let run = Run()
    run.pushSegment(Segment("One"))
    // `LiveSplitCore.Timer`, not Foundation's.
    return LiveSplitCore.Timer(run)!.intoShared()
}

@Suite struct EventSinkTests {
    @Test func aServerCommandStartsTheTimerAndReportsTheEvent() {
        let timer = makeTimer()
        let results = Results()
        let sink = EventSink(timer: timer, report: { results.append($0) }, decideReset: { .cancel })

        #expect(sink.handleCommand(#"{"command":"splitOrStart"}"#) == #"{"success":null}"#)
        #expect(results.all == [.event(.started)])
        #expect(timer.read().timer().currentPhase() == 1)  // Running
    }

    @Test func aRejectedCommandReportsTheError() {
        let results = Results()
        let sink = EventSink(
            timer: makeTimer(), report: { results.append($0) }, decideReset: { .cancel })

        let reply = sink.handleCommand(#"{"command":"split"}"#)
        #expect(reply == #"{"error":{"code":"NoRunInProgress"}}"#)
        #expect(results.all == [.error(.noRunInProgress)])
    }

    @Test func invalidJSONGetsInvalidCommand() {
        let sink = EventSink(timer: makeTimer(), report: { _ in }, decideReset: { .cancel })
        #expect(sink.handleCommand("not json").contains(#""code":"InvalidCommand""#))
    }

    @Test func theSinkKeepsTheTimerAlive() {
        let results = Results()
        let sink = EventSink(
            timer: makeTimer(), report: { results.append($0) }, decideReset: { .cancel })
        #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
    }

    @Test func encodesEventsForTheServer() {
        #expect(EventSink.encodeEvent(.splitted) == #"{"event":"Splitted"}"#)
    }
}
```

Replace `project.yml` with the version that adds the `LiveSplitCore` target, its build phase, the module and library search paths, and the integration tests' dependency on it:

```yaml
# The Xcode project (spec §4.1). Generate it with `xcodegen generate`; the
# generated LiveSplitOne.xcodeproj and App/Info.plist are not committed.
name: LiveSplitOne
options:
  bundleIdPrefix: dev.alexcosta
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
  # The generated Swift bindings must exist before the project lists them.
  preGenCommand: scripts/build-core.sh --bindings-only
settings:
  base:
    SWIFT_VERSION: "6.0"
    # The CLiveSplitCore module, and the Rust libraries its module map links.
    SWIFT_INCLUDE_PATHS: $(SRCROOT)/LiveSplitCore/CLiveSplitCore/include
    LIBRARY_SEARCH_PATHS: $(SRCROOT)/LiveSplitCore/lib
    # Unsigned builds (spec §2), ad-hoc signed so they run on Apple Silicon.
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
    # Development fallbacks. Releases pass the real version to xcodebuild
    # (spec §4.2), so no committed file holds a release's version.
    MARKETING_VERSION: "0.0.0"
    CURRENT_PROJECT_VERSION: "0"
    LSO_VERSION: 0.0.0-dev
targets:
  LiveSplitOne:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - target: LiveSplitCore
    info:
      path: App/Info.plist
      properties:
        CFBundleName: LiveSplit One
        CFBundleDisplayName: LiveSplit One for macOS
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        # The full version, such as 0.4.0-rc.2, which
        # CFBundleShortVersionString can't hold. The app shows this one.
        LSOVersion: $(LSO_VERSION)
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSPrincipalClass: NSApplication
        NSHighResolutionCapable: true
        NSLocalNetworkUsageDescription: >-
          LiveSplit One connects to the timer server you choose, such as
          livesplit-asr-bridge on another computer.
    settings:
      base:
        PRODUCT_NAME: LiveSplit One
        PRODUCT_MODULE_NAME: LiveSplitOne
        PRODUCT_BUNDLE_IDENTIFIER: dev.alexcosta.livesplit-one-macos
    scheme:
      testTargets:
        - LiveSplitOneUnitTests
        - LiveSplitOneHeadlessUITests
        - LiveSplitOneIntegrationTests
        - LiveSplitOneE2ETests

  # livesplit-core's generated Swift bindings and the hand-written wrapper for
  # core/'s additions (spec §4). An Xcode target, not a Swift package: Xcode
  # builds packages before any of the project's build phases, and this
  # target's phase must regenerate the bindings before they are compiled.
  LiveSplitCore:
    type: library.static
    platform: macOS
    sources:
      - LiveSplitCore/Wrapper
      - path: LiveSplitCore/Generated
        excludes: [".source"]
    settings:
      base:
        # The script writes into the repository and ~/.cargo.
        ENABLE_USER_SCRIPT_SANDBOXING: NO
    preBuildScripts:
      - name: Build core and bindings
        script: '"$SRCROOT/scripts/build-core.sh"'
        basedOnDependencyAnalysis: true
        outputFiles:
          - $(SRCROOT)/LiveSplitCore/lib/liblso_core.a
          - $(SRCROOT)/LiveSplitCore/lib/liblivesplit_core.a
          - $(SRCROOT)/LiveSplitCore/Generated/LiveSplitCore.swift
          - $(SRCROOT)/LiveSplitCore/CLiveSplitCore/include/livesplit_core.h
        # Written by the script: every file it read (spec §4.2).
        discoveredDependencyFile: $(DERIVED_FILE_DIR)/build-core.d

  # The test pyramid (spec §14.1). Unit and headless UI tests run inside the
  # app, so they can use its internals.
  LiveSplitOneUnitTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/Unit]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/LiveSplit One.app/Contents/MacOS/LiveSplit One
        BUNDLE_LOADER: $(TEST_HOST)
  LiveSplitOneHeadlessUITests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/HeadlessUI]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/LiveSplit One.app/Contents/MacOS/LiveSplit One
        BUNDLE_LOADER: $(TEST_HOST)
  # Not hosted: it checks the built app from outside, and links LiveSplitCore
  # itself.
  LiveSplitOneIntegrationTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/Integration]
    dependencies:
      - target: LiveSplitOne
        link: false
      - target: LiveSplitCore
    settings:
      base:
        # XcodeGen would otherwise host it in the app, by target name.
        TEST_HOST: ""
        BUNDLE_LOADER: ""
  LiveSplitOneE2ETests:
    type: bundle.ui-testing
    platform: macOS
    sources: [Tests/E2E]
    dependencies:
      - target: LiveSplitOne
    settings:
      base:
        TEST_TARGET_NAME: LiveSplitOne
```

Create `LiveSplitCore/Wrapper/EventSink.swift` with only:

```swift
import CLiveSplitCore
```

- [ ] **Step 5: Run the tests to verify they fail**

```bash
mise x -- xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' \
  -only-testing:LiveSplitOneIntegrationTests
```

Expected: build fails with `cannot find 'EventSink' in scope` and `cannot find type 'CommandResult' in scope`.

- [ ] **Step 6: Implement the wrapper**

Replace `LiveSplitCore/Wrapper/EventSink.swift`:

```swift
import CLiveSplitCore
import Foundation

/// An event livesplit-core reports after a command (its `src/event.rs`).
public enum TimerEvent: UInt32, Sendable {
    case started = 0
    case splitted = 1
    case finished = 2
    case reset = 3
    case splitUndone = 4
    case splitSkipped = 5
    case paused = 6
    case resumed = 7
    case pausesUndone = 8
    case pausesUndoneAndResumed = 9
    case comparisonChanged = 10
    case timingMethodChanged = 11
    case gameTimeInitialized = 12
    case gameTimeSet = 13
    case gameTimePaused = 14
    case gameTimeResumed = 15
    case loadingTimesSet = 16
    case customVariableSet = 17
}

/// Why livesplit-core rejected a command (its `src/event.rs`).
public enum TimerError: UInt32, Sendable, Error {
    case unsupported = 0
    case busy = 1
    case runAlreadyInProgress = 2
    case noRunInProgress = 3
    case runFinished = 4
    case negativeTime = 5
    case cantSkipLastSplit = 6
    case cantUndoFirstSplit = 7
    case alreadyPaused = 8
    case notPaused = 9
    case comparisonDoesntExist = 10
    case gameTimeAlreadyInitialized = 11
    case gameTimeAlreadyPaused = 12
    case gameTimeNotPaused = 13
    case couldNotParseTime = 14
    case timerPaused = 15
    case runnerDecidedAgainstReset = 16
}

/// A command's result, as the sink reports it.
public enum CommandResult: Equatable, Sendable {
    case event(TimerEvent?)
    case error(TimerError?)

    /// Decodes livesplit-core's C API encoding: an event is 0 or more, an
    /// error `e` is `-1 - e`. Numbers this version doesn't know give `nil`.
    init(raw: Int32) {
        if raw >= 0 {
            self = .event(TimerEvent(rawValue: UInt32(raw)))
        } else {
            self = .error(TimerError(rawValue: UInt32(-1 - raw)))
        }
    }
}

/// What to do when a reset has new best times, as in LiveSplit One's dialog.
public enum ResetDecision: UInt8, Sendable {
    case save = 0
    case discard = 1
    case cancel = 2
}

/// The event-reporting command sink from core/ (spec §5.3). Not the generated
/// `CommandSink`, which wraps a plain timer and reports nothing.
public final class EventSink: @unchecked Sendable {
    /// Called with every command's result, on the thread that ran the command.
    public typealias Report = @Sendable (CommandResult) -> Void
    /// Called when a reset needs a decision, on the thread that ran the
    /// command, which waits for the answer.
    public typealias DecideReset = @Sendable () -> ResetDecision

    private final class Callbacks {
        let report: Report
        let decideReset: DecideReset
        init(report: @escaping Report, decideReset: @escaping DecideReset) {
            self.report = report
            self.decideReset = decideReset
        }
    }

    private let ptr: UnsafeMutableRawPointer

    public init(timer: SharedTimerRef, report: @escaping Report, decideReset: @escaping DecideReset)
    {
        precondition(timer.ptr != nil)
        let context = Unmanaged.passRetained(Callbacks(report: report, decideReset: decideReset))
        let host = LsoHost(
            context: context.toOpaque(),
            report: { context, raw in
                Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                    .report(CommandResult(raw: raw))
            },
            decide_reset: { context in
                Unmanaged<Callbacks>.fromOpaque(context!).takeUnretainedValue()
                    .decideReset().rawValue
            },
            release: { context in
                Unmanaged<Callbacks>.fromOpaque(context!).release()
            }
        )
        ptr = LsoCommandSink_new(timer.ptr, host)
    }

    deinit {
        LsoCommandSink_drop(ptr)
    }

    /// Runs one server protocol message and returns the reply to send back.
    public func handleCommand(_ json: String) -> String {
        String(cString: LsoCommandSink_handle_command(ptr, json))
    }

    /// Encodes an event as LiveSplit One sends it to the server.
    public static func encodeEvent(_ event: TimerEvent) -> String {
        String(cString: LsoServerProtocol_encode_event(event.rawValue))
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper
```

Expected: `** TEST SUCCEEDED **` with the 5 new integration tests passing beside Task 1's; the lint prints nothing.

- [ ] **Step 8: Check a clean checkout builds**

```bash
# Remove everything generated, as in a fresh clone (the Rust build cache in
# core/target can stay).
rm -rf LiveSplitOne.xcodeproj App/Info.plist LiveSplitCore/Generated LiveSplitCore/lib \
  LiveSplitCore/CLiveSplitCore/include/livesplit_core.h
mise x -- xcodegen generate
xcodebuild build -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
```

Expected: `xcodegen generate` regenerates the bindings through `preGenCommand`, and the build runs the phase and succeeds (acceptance criterion: from a clean checkout).

- [ ] **Step 9: Check the phase is skipped when nothing changed**

```bash
build() { xcodebuild build -project LiveSplitOne.xcodeproj -scheme LiveSplitOne \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData; }
build > /dev/null
build | grep -c 'PhaseScriptExecution Build.*core.*and.*bindings'
touch core/src/lib.rs
build | grep -c 'PhaseScriptExecution Build.*core.*and.*bindings'
```

Expected: `0` (skipped), then `1` (ran again after a Rust source changed). Then `rm -rf build`.

- [ ] **Step 10: Check the universal build**

```bash
scripts/build-core.sh --release --universal
for lib in LiveSplitCore/lib/*.a; do lipo -archs "$lib"; done
```

Expected: `x86_64 arm64` for each. The first run adds the `x86_64-apple-darwin` target through `rust-toolchain.toml`.

- [ ] **Step 11: Update the spec and CONTRIBUTING**

In spec §4, replace the **LiveSplitCore** bullet with:

```markdown
- **LiveSplitCore** (Xcode static library target, `LiveSplitCore/`). The Swift
  bindings generated by livesplit-core's `bind_gen`, plus a hand-written
  wrapper for the extra functions, in one Swift module. Generated files are
  produced by the build, not edited. It is an Xcode target rather than a Swift
  package because Xcode builds packages before any build phase, and its build
  phase (section 4.2) must regenerate the bindings first.
```

In §4.1, change the `LiveSplitCore/` line to `├── LiveSplitCore/           static library target: generated bindings + wrapper`.

In `CONTRIBUTING.md`, under "Development setup", add after the `xcodegen generate` step:

```markdown
   `xcodegen generate` runs `scripts/build-core.sh --bindings-only`, and
   building in Xcode runs `scripts/build-core.sh`, which builds `core/` with
   Cargo and regenerates livesplit-core's Swift bindings when needed. The
   first build downloads and compiles livesplit-core and takes a few minutes.
```

- [ ] **Step 12: Commit and open the pull request**

```bash
git add scripts/build-core.sh LiveSplitCore Tests/Integration/EventSinkTests.swift project.yml \
  .gitignore CONTRIBUTING.md docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md
git status --short   # Expected: no generated file staged (Generated/, lib/, livesplit_core.h)
git commit -m "feat: build core and the Swift bindings into the app"
git push -u origin feat/livesplitcore-bindings
gh pr create --base main --title "feat: build core and the Swift bindings into the app" --body-file "$PR_BODY"
```

Stop here. The maintainer merges.

---

### Task 4: Check the bridge handshake with a native client (issue #7)

**Branch:** `test/bridge-handshake` · **PR title:** `test: check the bridge handshake with a native client` · **PR body:** `Closes #7`, using the pull request template, with the outputs from Steps 3 to 5.

**Files:**
- Create: `scripts/handshake-check.swift` (a native `URLSessionWebSocketTask` client)
- Modify: spec §8.1

**Interfaces:**
- Consumes: nothing from earlier tasks; it runs with `swift`, so it can be done in parallel with Tasks 2 and 3, and must be done before the Connect to Server issue (spec §17, item 3).
- Produces: the `Origin` decision in spec §8.1, used by the Connect to Server issue.

Key facts:
- **The bridge doesn't check `Origin`.** livesplit-asr-bridge accepts connections with tokio-tungstenite's `accept_async` (`src/server/thread.rs:165`), which takes no header callback, and reports a failed handshake as `HandshakeFailed { address, error }` (`thread.rs:168-183`), which its log shows.
- **On connect, the bridge asks first:** its first tick sends `getCurrentState` immediately (`thread.rs:193-194`, `Link::ask_state` at line 257), and it then expects answers in order. So "a reply to a command" means the client answering the bridge's command, and the bridge accepting the answer.
- **`URLSessionWebSocketTask` sends no `Origin` by default.** A scratch run against `nc -l 127.0.0.1 18999` captured this upgrade request: `GET /`, `Host`, `User-Agent: … CFNetwork/3860.600.21 Darwin/25.5.0`, `Sec-WebSocket-Key`, `Sec-WebSocket-Version: 13`, `Upgrade: websocket`, `Accept`, `Sec-WebSocket-Extensions: permessage-deflate`, `Accept-Language`, `Accept-Encoding`, `Connection: Upgrade`, and no `Origin`. Against a scratch tungstenite server it completed the handshake, answered `getCurrentState` with `{"success":{"state":"NotRunning"}}` and `splitOrStart` with `{"success":null}`.
- **Local network permission belongs to the app that runs the script:** run from Terminal, macOS asks whether Terminal may find devices on the local network (System Settings → Privacy & Security → Local Network). The app's own prompt (spec §8.1) comes later.

- [ ] **Step 1: Write the client**

`scripts/handshake-check.swift`:

```swift
// Connects to a LiveSplit One server (such as livesplit-asr-bridge) with
// URLSessionWebSocketTask, the client the app will use (spec §8.1), answers
// its commands and prints everything, to check the handshake (issue #7).
//
//   swift scripts/handshake-check.swift <url> [--origin <origin>] [--seconds <n>]
import Foundation

struct Options {
    var url: URL
    var origin: String?
    var seconds: Double = 30

    static func parse(_ arguments: [String]) -> Options? {
        var rest = arguments.dropFirst()
        guard var text = rest.popFirst() else { return nil }
        if !text.contains("://") { text = "ws://" + text }
        guard let url = URL(string: text), ["ws", "wss"].contains(url.scheme) else { return nil }
        var options = Options(url: url)
        while let flag = rest.popFirst() {
            switch (flag, rest.popFirst()) {
            case ("--origin", let value?): options.origin = value
            case ("--seconds", let value?): options.seconds = Double(value) ?? options.seconds
            default: return nil
            }
        }
        return options
    }
}

/// The reply a timer that has no run in progress gives.
func reply(to command: String) -> String {
    if command.contains(#""command":"getCurrentState""#) {
        return #"{"success":{"state":"NotRunning"}}"#
    }
    return #"{"success":null}"#
}

final class Delegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    /// Set before the script closes the connection itself, so that isn't
    /// reported as a failure.
    var closing = false

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("open: handshake succeeded")
    }

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        print("closed: code \(closeCode.rawValue)")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error, !closing {
            print("failed: \(error.localizedDescription)")
            if let response = task.response as? HTTPURLResponse {
                print("HTTP status \(response.statusCode)")
            }
            exit(1)
        }
    }
}

func receive(_ task: URLSessionWebSocketTask) {
    task.receive { result in
        switch result {
        case .success(.string(let text)):
            print("received: \(text)")
            let answer = reply(to: text)
            task.send(.string(answer)) { error in
                print(error.map { "send failed: \($0)" } ?? "sent: \(answer)")
            }
            receive(task)
        case .success(let other):
            print("received non-text message: \(other)")
            receive(task)
        case .failure(let error):
            print("receive failed: \(error.localizedDescription)")
        }
    }
}

guard let options = Options.parse(CommandLine.arguments) else {
    print("usage: swift scripts/handshake-check.swift <ws-url> [--origin <origin>] [--seconds <n>]")
    exit(2)
}
var request = URLRequest(url: options.url)
if let origin = options.origin {
    request.setValue(origin, forHTTPHeaderField: "Origin")
}
print("connecting to \(options.url.absoluteString), Origin: \(options.origin ?? "(not set)")")
let delegate = Delegate()
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
let task = session.webSocketTask(with: request)
task.resume()
receive(task)
DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) {
    delegate.closing = true
    task.cancel(with: .normalClosure, reason: nil)
    print("done after \(Int(options.seconds)) s")
    exit(0)
}
dispatchMain()
```

Run: `swift format lint --strict scripts/handshake-check.swift`
Expected: no output.

- [ ] **Step 2: Check what it sends, without a server**

```bash
nc -l 127.0.0.1 18999 > /tmp/upgrade.txt &
swift scripts/handshake-check.swift 127.0.0.1:18999 --seconds 3
cat /tmp/upgrade.txt
```

Expected: the script prints `connecting to ws://127.0.0.1:18999, Origin: (not set)`, and the request has no `Origin` line. Run it again with `--origin https://one.livesplit.org` and check the request has `Origin: https://one.livesplit.org`.

- [ ] **Step 3 (maintainer, optional, on the Mac): Against the bridge on the same Mac**

Start livesplit-asr-bridge's macOS build, then:
`swift scripts/handshake-check.swift ws://127.0.0.1:16834 --seconds 30`

Expected: `open: handshake succeeded`, `received: {"command":"getCurrentState"}`, `sent: {"success":{"state":"NotRunning"}}`; the bridge's Connection tab lists the timer under Connected timers as Not running. This separates handshake problems from network problems before Step 4.

- [ ] **Step 4 (maintainer, needs the gaming PC): Against the real bridge**

1. On the gaming PC, start livesplit-asr-bridge and copy a LAN address from the Connection tab, such as `ws://192.168.1.20:16834`.
2. On the Mac: `swift scripts/handshake-check.swift ws://192.168.1.20:16834 --seconds 120`. If macOS asks whether Terminal may find devices on the local network, click Allow.
3. Expected: as in Step 3, and the Mac's address appears under Connected timers on the PC.
4. While it runs, make the auto splitter act (start the game, or use the bridge's test controls if it has them). Expected: lines such as `received: {"command":"splitOrStart"}` and `sent: {"success":null}`, and no rejected command in the bridge's log.
5. Copy the script's output and the bridge's log lines for the connection into the pull request.

- [ ] **Step 5 (maintainer, only if Step 4 fails): Narrow it down**

1. Read the bridge's log for `HandshakeFailed` and its error.
2. Run again with `--origin https://one.livesplit.org`. If that connects and Step 4 didn't, the bridge needs an `Origin`.
3. If the script prints `failed: …` before `open`, check System Settings → Privacy & Security → Local Network for Terminal, and that `nc -vz 192.168.1.20 16834` reaches the PC.
4. Record what was found in the pull request. If the bridge needs a change, open an issue on livesplit-asr-bridge and link it.

- [ ] **Step 6: Record the result in the spec**

Replace the second bullet of spec §8.1 with the result. If Step 4 passed (expected):

```markdown
- The client is `URLSessionWebSocketTask`, and sends no `Origin` header:
  `URLSessionWebSocketTask` adds none, and livesplit-asr-bridge doesn't check
  it (it accepts with tungstenite's `accept_async`). A native client connected
  to the bridge on the gaming PC and answered its commands with no `Origin`
  (issue #7). A server that needs one is not supported in the first version.
```

- [ ] **Step 7: Commit and open the pull request**

```bash
git add scripts/handshake-check.swift docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md
git commit -m "test: check the bridge handshake with a native client"
git push -u origin test/bridge-handshake
gh pr create --base main --title "test: check the bridge handshake with a native client" --body-file "$PR_BODY"
```

Stop here. The maintainer merges.

---

### Task 5: Pull request checks (issue #8)

**Branch:** `ci/pull-request-checks` · **PR title:** `ci: add pull request checks` · **PR body:** `Closes #8`, using the pull request template.

**Files:**
- Create: `.github/actions/setup/action.yml` (Rust from `rust-toolchain.toml`, Rust cache, mise tools)
- Create: `.github/workflows/ci.yml` (`setup`, `lint`, `test`, `e2e`, `build`, `commitlint`)
- Create: `.github/workflows/pr-title.yml` (`pr-title`)
- Create: `scripts/build-app.sh` (the universal release `.app` in a `.zip`; also used by Task 6)
- Modify: `CONTRIBUTING.md`, `.github/pull_request_template.md` (local checks match CI)

**Interfaces:**
- Consumes: Tasks 1 to 3 (`project.yml`, `scripts/build-core.sh`, the test targets), `commitlint.config.mjs` (issue #2).
- Produces:
  - Check runs named exactly `setup`, `lint`, `test`, `e2e`, `build`, `commitlint`, `pr-title`, required in ruleset `24807167` ("main").
  - `scripts/build-app.sh <version>`: writes `dist/livesplit-one-macos-<version>-macos-universal.zip` containing `LiveSplit One.app`, after checking it holds arm64 and x86_64 and the expected versions and identifier.
  - `.github/actions/setup` with input `save-cache` (`'true'`/`'false'`).

Key facts:
- **Build once, test from it:** `setup` runs `xcodebuild build-for-testing` and passes `Build/Products` (the app, the test bundles and the `.xctestrun` file) to `test` and `e2e`, which run `xcodebuild test-without-building -xctestrun …`. `upload-artifact` doesn't keep file permissions, so the products travel as a tar.
- **What is cached:** Swatinem/rust-cache caches `~/.cargo` and `core/target`, as in livesplit-asr-bridge, with one key shared by every job, saved by `setup` only. Xcode's DerivedData isn't cached between runs: a fresh checkout gives every file a new modification time, so Xcode would rebuild the Swift anyway; sharing the test build covers "build the app once".
- **Xcode is chosen explicitly:** `macos-latest` is the macOS 26 arm64 image, whose newest and default Xcode is 26.6 (runner image 20260907; Xcode 27 isn't on it yet, see `actions/runner-images`, `images/macos/macos-26-arm64-Readme.md`). The setup action selects `/Applications/Xcode_$XCODE_VERSION.app`, so a change of the image's default can't silently change the build. Moving to Xcode 27 is a one-line change to `XCODE_VERSION` once an image ships it. 26.6 is also the oldest Xcode the project supports locally.
- **Rust comes from `rust-toolchain.toml`:** GitHub's macOS runners have rustup, and `rustup toolchain install` with no argument installs what the file names, including the `x86_64-apple-darwin` target for `build`. `dtolnay/rust-toolchain` isn't used.
- **On push to `main`** only `setup` runs, which builds and saves the Rust cache that pull requests restore (spec §15).
- **Required checks:** the existing ruleset `24807167` has `deletion`, `non_fast_forward`, `required_linear_history`, `required_signatures` and `pull_request` (squash only, conversations resolved). Rulesets are replaced as a whole, so Step 8 sends every existing rule plus `required_status_checks`. `15368` is the GitHub Actions app's id (`gh api apps/github-actions --jq .id`).
- `pr-title.yml` runs on `pull_request_target`, which uses the workflow file from `main`, so it only runs from the next pull request on.

- [ ] **Step 1: Write the setup action**

`.github/actions/setup/action.yml`:

```yaml
# Selects the Xcode the project builds with, installs the Rust toolchain from
# rust-toolchain.toml and the tools pinned in mise.toml, and restores the Rust
# cache. Every CI job shares one cache key,
# so the `setup` job compiles the dependencies once and the other jobs reuse
# them.
name: Setup
description: Select Xcode, install Rust and the mise tools, and restore the Rust cache

inputs:
  save-cache:
    description: Whether to save the Rust cache at the end of the job
    required: false
    default: 'false'

runs:
  using: composite
  steps:
    # The runner image has several Xcodes; choose one explicitly so the image's
    # default changing never changes the build. Raise this when an image ships
    # a newer Xcode (the list is in actions/runner-images'
    # images/macos/macos-26-arm64-Readme.md).
    - name: Select Xcode
      shell: bash
      env:
        XCODE_VERSION: '26.6'
      run: |
        app="/Applications/Xcode_${XCODE_VERSION}.app"
        if [ ! -d "$app" ]; then
          echo "::error::Xcode ${XCODE_VERSION} isn't on this runner. Installed:" >&2
          ls -d /Applications/Xcode_*.app >&2
          exit 1
        fi
        sudo xcode-select --switch "$app/Contents/Developer"
        xcodebuild -version
    # rustup is preinstalled on GitHub's macOS runners. With no arguments it
    # installs the toolchain, components and targets rust-toolchain.toml names.
    - name: Install the Rust toolchain
      shell: bash
      run: rustup toolchain install
    - uses: Swatinem/rust-cache@v2
      with:
        workspaces: core
        shared-key: ci
        save-if: ${{ inputs.save-cache }}
    - uses: jdx/mise-action@v4
```

- [ ] **Step 2: Write `scripts/build-app.sh`**

```bash
#!/usr/bin/env bash
# Builds the universal (Apple Silicon and Intel) release app with the version
# embedded, and zips it into dist/ (spec §15).
#   scripts/build-app.sh <version>    e.g. 0.4.0 or 0.4.0-rc.2
set -euo pipefail

version=${1:?usage: build-app.sh <version>}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
derived=build/DerivedData
app="$derived/Build/Products/Release/LiveSplit One.app"
zip="dist/livesplit-one-macos-$version-macos-universal.zip"
# Bundle versions must be numbers, so candidates use the X.Y.Z part there.
# The full version goes in LSOVersion, which the app shows.
short=${version%%-*}

xcodegen generate
xcodebuild build \
  -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$short" CURRENT_PROJECT_VERSION="$short" LSO_VERSION="$version"

# Check what is about to ship.
executable="$app/Contents/MacOS/LiveSplit One"
archs=$(lipo -archs "$executable")
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "expected arm64 and x86_64, got: $archs" >&2
  exit 1
fi
plist="$app/Contents/Info.plist"
for key in CFBundleShortVersionString:"$short" LSOVersion:"$version" \
  CFBundleIdentifier:dev.alexcosta.livesplit-one-macos; do
  actual=$(/usr/libexec/PlistBuddy -c "Print :${key%%:*}" "$plist")
  if [[ "$actual" != "${key#*:}" ]]; then
    echo "${key%%:*} is '$actual', expected '${key#*:}'" >&2
    exit 1
  fi
done

mkdir -p dist
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
ls dist
```

Run: `chmod +x scripts/build-app.sh && mise x -- shellcheck scripts/build-app.sh`
Expected: no output.

Run: `scripts/build-app.sh 0.1.0-rc.1 && unzip -l dist/livesplit-one-macos-0.1.0-rc.1-macos-universal.zip | head -5`
Expected: the build succeeds, and the listing starts with `LiveSplit One.app/`. Then `rm -rf build dist`.

- [ ] **Step 3: Write `ci.yml`**

```yaml
name: CI

on:
  pull_request:
    types: [opened, reopened, synchronize]
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: read

concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

env:
  # Line numbers only, not full debug info: much smaller caches.
  CARGO_PROFILE_DEV_DEBUG: line-tables-only
  DERIVED_DATA: build/DerivedData

jobs:
  # Builds core/ and the app with its tests once, saves the Rust cache, and
  # hands the test build to `test` and `e2e`. On push to main it only builds,
  # to save the cache new pull requests restore: GitHub lets a pull request
  # read its base branch's caches, not other pull requests' (spec §15).
  setup:
    name: setup
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup
        with:
          save-cache: 'true'
      - run: cargo clippy --all-targets --locked --manifest-path core/Cargo.toml
      - run: cargo test --no-run --locked --manifest-path core/Cargo.toml
      - run: xcodegen generate
      - name: Build the app and its tests
        run: >-
          xcodebuild build-for-testing -project LiveSplitOne.xcodeproj
          -scheme LiveSplitOne -destination 'platform=macOS'
          -derivedDataPath "$DERIVED_DATA"
      # upload-artifact drops file permissions, so the build travels as a tar.
      - name: Pack the test build
        if: github.event_name == 'pull_request'
        run: tar -C "$DERIVED_DATA" -cf test-build.tar Build/Products
      - if: github.event_name == 'pull_request'
        uses: actions/upload-artifact@v7
        with:
          name: test-build
          path: test-build.tar
          retention-days: 1
          if-no-files-found: error

  # These jobs use `!cancelled()` so they still run when `setup` fails: a job
  # skipped because `setup` failed reports as success and would not block the
  # merge, so they run anyway and report the real failure.
  lint:
    name: lint
    needs: setup
    if: ${{ !cancelled() && github.event_name == 'pull_request' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup
      - run: cargo fmt --check --manifest-path core/Cargo.toml
      - run: cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
      - run: swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts

  test:
    name: test
    needs: setup
    if: ${{ !cancelled() && github.event_name == 'pull_request' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup
      - run: cargo test --locked --manifest-path core/Cargo.toml
      - uses: actions/download-artifact@v8
        with:
          name: test-build
      - run: mkdir -p "$DERIVED_DATA" && tar -C "$DERIVED_DATA" -xf test-build.tar
      - name: Unit, headless UI and integration tests
        run: >-
          xcodebuild test-without-building
          -xctestrun "$(ls "$DERIVED_DATA"/Build/Products/*.xctestrun)"
          -destination 'platform=macOS' -skip-testing:LiveSplitOneE2ETests

  e2e:
    name: e2e
    needs: setup
    if: ${{ !cancelled() && github.event_name == 'pull_request' }}
    runs-on: macos-latest
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: test-build
      - run: mkdir -p "$DERIVED_DATA" && tar -C "$DERIVED_DATA" -xf test-build.tar
      - name: E2E tests
        run: >-
          xcodebuild test-without-building
          -xctestrun "$(ls "$DERIVED_DATA"/Build/Products/*.xctestrun)"
          -destination 'platform=macOS' -only-testing:LiveSplitOneE2ETests

  build:
    name: build
    needs: setup
    if: ${{ !cancelled() && github.event_name == 'pull_request' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup
      - run: scripts/build-app.sh 0.0.0-dev
      - uses: actions/upload-artifact@v7
        with:
          name: app
          path: dist/*.zip
          if-no-files-found: error

  commitlint:
    name: commitlint
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: wagoid/commitlint-github-action@v6
```

- [ ] **Step 4: Write `pr-title.yml`**

```yaml
name: PR title

on:
  pull_request_target:
    types: [opened, reopened, edited, synchronize]

permissions:
  pull-requests: read

jobs:
  pr-title:
    name: pr-title
    runs-on: ubuntu-latest
    steps:
      - uses: amannn/action-semantic-pull-request@v6
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            perf
            refactor
            docs
            test
            build
            ci
            style
            chore
```

This workflow never checks out pull request code, which is what makes `pull_request_target` safe for pull requests from forks.

- [ ] **Step 5: Make the documented checks match CI**

In `CONTRIBUTING.md`, replace the block under "Before pushing, run the same checks CI runs:" with:

```sh
cargo fmt --check --manifest-path core/Cargo.toml
cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
cargo test --locked --manifest-path core/Cargo.toml
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
```

In `.github/pull_request_template.md`, replace the checks item with:

```markdown
- [ ] The Rust checks (`cargo fmt --check`, `cargo clippy … -D warnings`,
      `cargo test --locked`), `swift format lint --strict` and
      `xcodebuild test` pass locally (see CONTRIBUTING.md).
```

- [ ] **Step 6: Lint the workflows**

Run: `mise x -- actionlint`
Expected: no output. (actionlint runs shellcheck on every `run:` step; mise provides both.)

- [ ] **Step 7: Commit, push and check the checks**

```bash
git add .github/actions .github/workflows scripts/build-app.sh CONTRIBUTING.md .github/pull_request_template.md
git commit -m "ci: add pull request checks"
git push -u origin ci/pull-request-checks
gh pr create --base main --title "ci: add pull request checks" --body-file "$PR_BODY"
gh pr checks --watch
```

Expected: `setup`, `lint`, `test`, `e2e`, `build` and `commitlint` pass (`pr-title` only runs from the next pull request). The `build` run has an `app` artifact with the `.zip`.

Prove the checks fail on real problems, with one throwaway commit:

```bash
sed -i '' 's/"timer-window"/"broken-window"/' App/AppDelegate.swift
sed -i '' 's/^    static let fallback/    static  let fallback/' App/AppVersion.swift
git commit -am "Bad commit message"
git push
gh pr checks --watch
```

Expected: `commitlint` fails (message), `lint` fails (`swift format`), `test` fails (`TimerWindowTests`), `e2e` fails (`LaunchTests`); `setup` and `build` pass. Then remove the commit:

```bash
git reset --hard HEAD~1
git push --force-with-lease
gh pr checks --watch
```

Expected: all checks pass again.

- [ ] **Step 8: Confirm the check run names**

Run: `gh api repos/alexcosta97/livesplit-one-macos/commits/$(git rev-parse HEAD)/check-runs --jq '.check_runs[].name' | sort -u`
Expected exactly: `build`, `commitlint`, `e2e`, `lint`, `setup`, `test`.

Stop here. The maintainer merges.

- [ ] **Step 9 (coordinator, after the merge): Require the checks on `main`**

```bash
gh api repos/alexcosta97/livesplit-one-macos/rulesets/24807167 \
  | jq '{name, target, enforcement, conditions, bypass_actors,
         rules: ([.rules[] | select(.type != "required_status_checks")] + [{
           type: "required_status_checks",
           parameters: {
             strict_required_status_checks_policy: false,
             do_not_enforce_on_create: false,
             required_status_checks: [
               {context: "setup", integration_id: 15368},
               {context: "lint", integration_id: 15368},
               {context: "test", integration_id: 15368},
               {context: "e2e", integration_id: 15368},
               {context: "build", integration_id: 15368},
               {context: "commitlint", integration_id: 15368},
               {context: "pr-title", integration_id: 15368}
             ]}}])}' \
  | gh api -X PUT repos/alexcosta97/livesplit-one-macos/rulesets/24807167 --input - \
      --jq '[.rules[].type]'
```

Expected: `["deletion","non_fast_forward","required_linear_history","required_signatures","pull_request","required_status_checks"]`.

- [ ] **Step 10 (coordinator): Verify on the next pull request**

On Task 6's pull request, `gh pr checks` lists all seven checks, including `pr-title`, as required.

---

### Task 6: Release pipeline (issue #9)

**Branch:** `ci/release-pipeline` · **PR title:** `ci: add the release pipeline` · **PR body:** `Closes #9`, using the pull request template.

**Files:**
- Create: `cliff.toml` (version and release note rules, as in livesplit-asr-bridge)
- Create: `scripts/release/next-version.sh`, `scripts/release/notes.sh`, `scripts/release/test-release-scripts.sh` (as in livesplit-asr-bridge)
- Create: `.github/workflows/build.yml` (reusable: builds and packages the app)
- Create: `.github/workflows/release.yml` (release candidates, approval, full release)
- Create: `.github/workflows/release-scripts.yml` (script tests and a package build, when release files change)
- Modify: `CONTRIBUTING.md` (releases)

**Interfaces:**
- Consumes: `scripts/build-app.sh` and `.github/actions/setup` (Task 5); `mise.toml` with git-cliff and shellcheck (issue #2); the `release` environment.
- Produces:
  - `scripts/release/next-version.sh` — no arguments, run at the commit being released. Prints `key=value` lines, also appended to `$GITHUB_OUTPUT`: `release` (`true`/`false`), `version`, `rc_version`, `rc_tag`, `previous_rc_tag`, `last_full_tag`.
  - `scripts/release/notes.sh rc [previous_rc_tag]` and `scripts/release/notes.sh full`.
  - `.github/workflows/build.yml` — `workflow_call` with inputs `version`, `ref` and `artifact-name`; uploads one artifact named `<artifact-name>` with the `.zip`.
  - Workflow `Release scripts`, advisory (not required: GitHub keeps a path-filtered required check pending forever on pull requests that don't match).

Key facts:
- The release scripts, `cliff.toml` and `release.yml` are livesplit-asr-bridge's (at `59d39474dd03da8ec05d929c8a91bba53fd77c4e`), whose design notes still apply: release candidates are hidden from version calculation with `tag_pattern`, not `ignore_tags`; `git cliff --bumped-version` never signals "nothing to release", so `next-version.sh` compares with the last full tag; no `no_increment_regex`. The only changes: one build artifact instead of one per target, no wiki step, and mise installs only what each Linux job needs, because XcodeGen's mise entry is macOS-only (`os = ["macos"]` in mise's registry).
- **The `release` environment already exists** with the maintainer (`alexcosta97`, id `23384791`) as required reviewer: `gh api repos/alexcosta97/livesplit-one-macos/environments/release` shows a `required_reviewers` rule. Step 7 only checks it.

- [ ] **Step 1: Write `cliff.toml`**

```toml
# Release rules: see spec §14 and CONTRIBUTING.md.
[changelog]
# Only the groups: scripts/release/notes.sh adds the headings.
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | striptags | trim }}
{% for commit in commits %}- {% if commit.scope %}**{{ commit.scope }}:** {% endif %}{{ commit.message | upper_first }}
{% endfor %}{% endfor %}
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true     # non-conventional commits never cause a release
filter_commits = true            # commits no parser matches are dropped
protect_breaking_commits = true  # a breaking docs/chore/refactor commit still bumps
# Only full releases count as tags. Release candidates are left out here, not
# with ignore_tags, so --unreleased always starts at the last full release.
tag_pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
sort_commits = "oldest"
commit_parsers = [
  # field = "breaking" catches both `type!:` and a BREAKING CHANGE footer.
  { field = "breaking", pattern = "true", group = "<!-- 0 -->Breaking changes" },
  { message = "^feat", group = "<!-- 1 -->Features" },
  { message = "^fix", group = "<!-- 2 -->Bug fixes" },
  { message = "^perf", group = "<!-- 3 -->Performance" },
  # Skipped before the bump is worked out. Not no_increment_regex, which would
  # also ignore a breaking `refactor!:`.
  { message = "^(docs|chore|ci|test|refactor|style|build)", skip = true },
]

[bump]
features_always_bump_minor = true   # feat bumps minor, also below 1.0.0
breaking_always_bump_major = false  # breaking bumps minor below 1.0.0, major from 1.0.0
initial_tag = "v0.1.0"
```

- [ ] **Step 2: Write the failing script tests**

`scripts/release/test-release-scripts.sh`:

```bash
#!/usr/bin/env bash
# Tests next-version.sh and notes.sh against temporary git repositories.
# Needs git, git-cliff and jq.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
failures=0

# Isolate from the user's git config (signing, hooks, default branch).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

new_repo() {
  repo=$(mktemp -d)
  cd "$repo"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com
  cp "$root/cliff.toml" .
}

commit() { git commit -q --allow-empty -m "$1"; }
tag() { git tag "$1"; }

next() { "$root/scripts/release/next-version.sh" 2>/dev/null; }

expect() { # description, key, expected value
  local actual
  # `|| true` so a script that fails reports FAIL instead of ending the run.
  actual=$(next | sed -n "s/^$2=//p") || true
  if [[ "$actual" == "$3" ]]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: $2 is '$actual', expected '$3'"
    failures=$((failures + 1))
  fi
}

expect_notes() { # description, expected substring, notes.sh args...
  local description=$1 needle=$2 notes
  shift 2
  notes=$("$root/scripts/release/notes.sh" "$@" 2>/dev/null) || true
  if [[ "$notes" == *"$needle"* ]]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description: notes do not contain '$needle':"
    echo "$notes"
    failures=$((failures + 1))
  fi
}

# No releases yet.
new_repo
commit "chore: initial commit"
commit "docs: add readme"
expect "docs-only history before any release: no release" release false

commit "feat: add window"
expect "first releasing commit: release" release true
expect "first release is 0.1.0" version 0.1.0
expect "first release candidate is rc.1" rc_tag v0.1.0-rc.1
expect "no previous candidate" previous_rc_tag ""
tag v0.1.0-rc.1
expect "re-run on a tagged commit reuses its tag" rc_tag v0.1.0-rc.1

commit "fix: correct title"
expect "second candidate keeps the version" version 0.1.0
expect "second candidate is rc.2" rc_tag v0.1.0-rc.2
expect "previous candidate is rc.1" previous_rc_tag v0.1.0-rc.1
expect_notes "candidate notes list what is new since rc.1" "Correct title" rc v0.1.0-rc.1
expect_notes "candidate notes include all changes" "Add window" rc v0.1.0-rc.1
tag v0.1.0-rc.2

# First full release.
tag v0.1.0
commit "docs: explain setup"
expect "docs-only since a full release: no release" release false

commit "fix: handle reconnects"
expect "fix bumps patch" version 0.1.1
expect "count restarts for a new version" rc_tag v0.1.1-rc.1
expect "last full release found" last_full_tag v0.1.0
tag v0.1.1-rc.1

commit "feat: add port setting"
expect "feat after a fix bumps minor, counting from the last full release" version 0.2.0
expect "count restarts when the version changes" rc_tag v0.2.0-rc.1
expect_notes "full notes count from the last full release, not the candidate" "Handle reconnects" full

commit "feat!: change settings format"
expect "breaking change below 1.0.0 bumps minor" version 0.2.0

# From 1.0.0, breaking changes bump major.
tag v1.0.0
commit "refactor!: drop old config"
expect "breaking refactor from 1.0.0 bumps major" version 2.0.0

if ((failures > 0)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
```

Run: `chmod +x scripts/release/test-release-scripts.sh`

- [ ] **Step 3: Run the tests to verify they fail**

Run: `mise x -- scripts/release/test-release-scripts.sh`
Expected: every test prints `FAIL` (the scripts don't exist yet), and the script exits 1.

- [ ] **Step 4: Write `next-version.sh`**

`scripts/release/next-version.sh`:

```bash
#!/usr/bin/env bash
# Works out whether the commits since the last full release need a release,
# and if so its version and release candidate tag. Run at the commit being
# released, with all tags fetched. Prints key=value lines, also appended to
# $GITHUB_OUTPUT when set.
set -euo pipefail

emit() {
  echo "$1=$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >>"$GITHUB_OUTPUT"
  fi
}

last_full_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null || true)
next=$(git cliff --bumped-version 2>/dev/null)

# git-cliff prints the current tag when nothing needs a release, and
# initial_tag when there are no tags, so check both cases explicitly.
if [[ -n "$last_full_tag" ]]; then
  [[ "$next" != "$last_full_tag" ]] && release=true || release=false
else
  releasing=$(git cliff --unreleased --context 2>/dev/null | jq '[.[].commits | length] | add // 0')
  ((releasing > 0)) && release=true || release=false
fi

version="" rc_version="" rc_tag="" previous_rc_tag=""
if [[ "$release" == true ]]; then
  version=${next#v}
  existing=$(git tag --points-at HEAD --list "v${version}-rc.*" | sort -V | tail -n1)
  last_rc=$(git tag --list "v${version}-rc.*" | sed -E 's/.*-rc\.([0-9]+)$/\1/' | sort -n | tail -n1)
  if [[ -n "$existing" ]]; then
    # A re-run for a commit that already has a candidate reuses it.
    rc_tag=$existing
    number=${existing##*-rc.}
    previous=$(git tag --list "v${version}-rc.*" | sed -E 's/.*-rc\.([0-9]+)$/\1/' | sort -n | awk -v n="$number" '$1 < n' | tail -n1)
  else
    number=$((${last_rc:-0} + 1))
    rc_tag="v${version}-rc.${number}"
    previous=$last_rc
  fi
  rc_version="${version}-rc.${number}"
  [[ -n "$previous" ]] && previous_rc_tag="v${version}-rc.${previous}"
fi

emit release "$release"
emit version "$version"
emit rc_version "$rc_version"
emit rc_tag "$rc_tag"
emit previous_rc_tag "$previous_rc_tag"
emit last_full_tag "$last_full_tag"
```

- [ ] **Step 5: Write `notes.sh`**

`scripts/release/notes.sh`:

```bash
#!/usr/bin/env bash
# Release notes for the commit at HEAD, on stdout.
#   notes.sh rc [previous_rc_tag]  notes for a release candidate
#   notes.sh full                  notes for a full release
set -euo pipefail

last_full_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null || true)
since=${last_full_tag:-the start of the project}

section() { # heading, git-cliff range arguments...
  local heading=$1 body
  shift
  body=$(git cliff "$@" --strip all 2>/dev/null)
  printf '## %s\n\n' "$heading"
  if [[ -n "${body//[[:space:]]/}" ]]; then
    printf '%s\n\n' "$body"
  else
    printf 'No user-facing changes.\n\n'
  fi
}

case "${1:-}" in
  rc)
    if [[ -n "${2:-}" ]]; then
      section "New since $2" "$2..HEAD"
    fi
    section "All changes since $since" --unreleased
    ;;
  full)
    section "Changes since $since" --unreleased
    ;;
  *)
    echo "usage: notes.sh rc [previous_rc_tag] | notes.sh full" >&2
    exit 2
    ;;
esac
```

Run: `chmod +x scripts/release/next-version.sh scripts/release/notes.sh`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mise x -- scripts/release/test-release-scripts.sh && mise x -- shellcheck scripts/*.sh scripts/release/*.sh`
Expected: every line starts with `ok`, the last is `all tests passed`, and shellcheck prints nothing.

- [ ] **Step 7: Write the workflows**

`.github/workflows/build.yml`:

```yaml
name: Build

on:
  workflow_call:
    inputs:
      version:
        description: Version embedded in the app, e.g. 0.4.0 or 0.4.0-rc.2
        required: true
        type: string
      ref:
        description: Commit to build
        required: true
        type: string
      artifact-name:
        description: Name of the uploaded artifact
        required: true
        type: string

permissions:
  contents: read

jobs:
  package:
    name: package
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ inputs.ref }}
      # Pull requests (the release-scripts `package` job) restore the cache but
      # don't save it.
      - uses: ./.github/actions/setup
        with:
          save-cache: ${{ github.ref == 'refs/heads/main' }}
      - run: scripts/build-app.sh "$VERSION"
        env:
          VERSION: ${{ inputs.version }}
      - uses: actions/upload-artifact@v7
        with:
          name: ${{ inputs.artifact-name }}
          path: dist/*.zip
          if-no-files-found: error
```

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: read

# A newer merge cancels an older run, including a release candidate still
# waiting for approval, so only the latest candidate can be promoted.
concurrency:
  group: release
  cancel-in-progress: true

jobs:
  version:
    name: version
    runs-on: ubuntu-latest
    outputs:
      release: ${{ steps.next.outputs.release }}
      version: ${{ steps.next.outputs.version }}
      rc_version: ${{ steps.next.outputs.rc_version }}
      rc_tag: ${{ steps.next.outputs.rc_tag }}
      previous_rc_tag: ${{ steps.next.outputs.previous_rc_tag }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      # Only git-cliff: XcodeGen in mise.toml is macOS-only.
      - uses: jdx/mise-action@v4
        with:
          install_args: git-cliff
      - id: next
        run: scripts/release/next-version.sh

  build-candidate:
    name: build candidate
    needs: version
    if: needs.version.outputs.release == 'true'
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ needs.version.outputs.rc_version }}
      ref: ${{ github.sha }}
      artifact-name: candidate

  candidate:
    name: publish release candidate
    needs: [version, build-candidate]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      # Only git-cliff: XcodeGen in mise.toml is macOS-only.
      - uses: jdx/mise-action@v4
        with:
          install_args: git-cliff
      - uses: actions/download-artifact@v8
        with:
          name: candidate
          path: dist
      - name: Publish the pre-release
        env:
          GH_TOKEN: ${{ github.token }}
          RC_TAG: ${{ needs.version.outputs.rc_tag }}
          PREVIOUS_RC_TAG: ${{ needs.version.outputs.previous_rc_tag }}
        run: |
          scripts/release/notes.sh rc "$PREVIOUS_RC_TAG" > notes.md
          if gh release view "$RC_TAG" > /dev/null 2>&1; then
            gh release upload "$RC_TAG" dist/* --clobber
          else
            gh release create "$RC_TAG" dist/* --prerelease --target "$GITHUB_SHA" \
              --title "$RC_TAG" --notes-file notes.md
          fi

  approve:
    name: approve release
    needs: [version, candidate]
    runs-on: ubuntu-latest
    environment: release
    steps:
      - run: echo "Promoting ${{ needs.version.outputs.rc_tag }} to v${{ needs.version.outputs.version }}"

  build-final:
    name: build release
    needs: [version, approve]
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ needs.version.outputs.version }}
      ref: ${{ github.sha }}
      artifact-name: final

  release:
    name: publish release
    needs: [version, build-final]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      # Only git-cliff: XcodeGen in mise.toml is macOS-only.
      - uses: jdx/mise-action@v4
        with:
          install_args: git-cliff
      - uses: actions/download-artifact@v8
        with:
          name: final
          path: dist
      - name: Publish the release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: v${{ needs.version.outputs.version }}
        run: |
          scripts/release/notes.sh full > notes.md
          gh release create "$TAG" dist/* --latest --target "$GITHUB_SHA" \
            --title "$TAG" --notes-file notes.md
```

`.github/workflows/release-scripts.yml`:

```yaml
name: Release scripts

# Only runs when release files change, so it never slows down or blocks normal
# CI. For the same reason it is not a required check: GitHub keeps a
# path-filtered required check pending forever on pull requests that don't
# match the paths.
on:
  pull_request:
    types: [opened, reopened, synchronize]
    paths:
      - cliff.toml
      - mise.toml
      - project.yml
      - scripts/**
      - .github/actions/setup/**
      - .github/workflows/build.yml
      - .github/workflows/release.yml
      - .github/workflows/release-scripts.yml

permissions:
  contents: read

jobs:
  release-scripts:
    name: release-scripts
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      # XcodeGen in mise.toml is macOS-only, and not needed here.
      - uses: jdx/mise-action@v4
        with:
          install_args: git-cliff shellcheck
      - run: shellcheck scripts/*.sh scripts/release/*.sh
      - run: scripts/release/test-release-scripts.sh

  # Builds and packages the app the way a release does, so packaging changes
  # are checked before they reach a release.
  package:
    name: package
    uses: ./.github/workflows/build.yml
    with:
      version: 0.0.0-dev
      ref: ${{ github.event.pull_request.head.sha }}
      artifact-name: package-test
```

Check the environment and lint:

```bash
gh api repos/alexcosta97/livesplit-one-macos/environments/release \
  --jq '[.protection_rules[] | select(.type == "required_reviewers") | .reviewers[].reviewer.login]'
mise x -- actionlint
```

Expected: `["alexcosta97"]`, then no output.

In `CONTRIBUTING.md`, make the "Releases" section say what livesplit-asr-bridge's says, and add: "The release is a universal (Apple Silicon and Intel) `.app` in a `.zip`, ad-hoc signed and not notarised, so users open it once with System Settings → Privacy & Security → Open Anyway." Add to "Development setup": "For the release scripts and workflow linting, run `scripts/release/test-release-scripts.sh` and `actionlint` with the tools from `mise install`. The same tests run on pull requests that change release files."

- [ ] **Step 8: Commit and open the pull request**

```bash
git add cliff.toml scripts/release .github/workflows/build.yml .github/workflows/release.yml \
  .github/workflows/release-scripts.yml CONTRIBUTING.md
git commit -m "ci: add the release pipeline"
git push -u origin ci/release-pipeline
gh pr create --base main --title "ci: add the release pipeline" --body-file "$PR_BODY"
gh pr checks --watch
```

Expected: the seven required checks pass, and so do `release-scripts` and `package`.

Stop here. The maintainer merges.

- [ ] **Step 9 (coordinator and maintainer, after the merge): Verify the first release**

This merge is `ci:`, but `main` already has Task 1's `feat:` commit and no release exists, so the first run releases `0.1.0`:

1. `gh run watch` on the Release run. Expected: `version` outputs `release=true`, `version=0.1.0`, `rc_tag=v0.1.0-rc.1`; `build candidate / package` succeeds; pre-release `v0.1.0-rc.1` has `livesplit-one-macos-0.1.0-rc.1-macos-universal.zip` and notes listing "Add the Xcode project and an empty app"; `approve release` waits.
2. (maintainer) Download the zip on the Apple Silicon Mac, open the app (System Settings → Privacy & Security → Open Anyway the first time) and check `mdls -name kMDItemVersion "LiveSplit One.app"` shows `0.1.0`; `defaults read "$PWD/LiveSplit One.app/Contents/Info" LSOVersion` shows `0.1.0-rc.1`. If an Intel Mac is available, open it there too.
3. The first time another pull request merges while a candidate waits for approval, check the older run's `approve release` is cancelled. If it isn't, fix the workflow in a follow-up pull request and record it in the spec.
4. When the maintainer approves: full release `v0.1.0`, marked Latest, on the same commit as `v0.1.0-rc.1`, whose app's `LSOVersion` is `0.1.0`.

---

### Task 7: Dependency updates with Renovate (issue #10)

**Branch:** `ci/renovate` · **PR title:** `ci: add Renovate configuration` · **PR body:** `Closes #10`, using the pull request template.

**Files:**
- Create: `renovate.json`
- Modify: `CONTRIBUTING.md` (dependency updates), spec §15

**Interfaces:**
- Consumes: the required checks (Task 5); `core/Cargo.toml` and `core/Cargo.lock` (Task 2); `project.yml` (Task 3); the workflows and `mise.toml`.
- Produces: weekly pull requests titled `fix(deps): …` (crates that ship, the LiveSplit crates, Swift packages that ship, `Cargo.lock` refreshes), `ci(deps): …` (GitHub Actions) or `chore(deps): …` (mise tools, development-only crates); the Dependency Dashboard issue; labels `dependencies` and `livesplit`.

Key facts, checked against Renovate's source (`lib/modules/manager/util.ts`, `applyGitSource`; `lib/modules/manager/cargo/schema.ts`):
- **A Cargo git dependency pinned by `rev` is updated:** Renovate uses the `git-refs` datasource with the git URL as `packageName` and the `rev` as `currentDigest`, and replaces the `rev` string. The dependency name stays the Cargo key (`livesplit-core`, `livesplit-core-capi`), so the LiveSplit rule matches on `matchDepNames`, and grouping makes both move to the same new revision in one pull request.
- **Renovate's Swift manager only reads `Package.swift`.** Swift packages for the app will be declared in `project.yml`'s `packages:` (XcodeGen: `url:` with `from:` or `exactVersion:`), so a regex custom manager reads those. None exists yet; it is ready for the first (the TOML library, spec §11).
- The configuration is committed before the app is installed, so the app skips its onboarding pull request, whose title would fail `pr-title`. The labels `dependencies` and `livesplit` already exist in the repository; Step 1 only gives them descriptions.
- Automerge stays off: only the maintainer merges.

- [ ] **Step 1 (coordinator): Describe the labels**

```bash
gh label edit dependencies --color 0366D6 --description "Dependency updates, opened by Renovate"
gh label edit livesplit --color D4A72C --description "Updates to the LiveSplit crates"
```

- [ ] **Step 2: Write `renovate.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", ":semanticCommits", "schedule:weekly"],
  "semanticCommitType": "chore",
  "semanticCommitScope": "deps",
  "platformCommit": "enabled",
  "automerge": false,
  "labels": ["dependencies"],
  "prConcurrentLimit": 5,
  "prHourlyLimit": 2,
  "lockFileMaintenance": { "enabled": true },
  "customManagers": [
    {
      "customType": "regex",
      "description": "Swift packages in project.yml, which Renovate's swift manager doesn't read",
      "managerFilePatterns": ["/^project\\.yml$/"],
      "matchStrings": [
        "url: https://github\\.com/(?<depName>[^/\\s]+/[^/\\s]+?)(?:\\.git)?\\s+(?:exactVersion|from): \"?(?<currentValue>[^\"\\s]+)\"?"
      ],
      "datasourceTemplate": "github-tags",
      "depTypeTemplate": "swift-package"
    }
  ],
  "packageRules": [
    {
      "description": "Crates that ship in the app: fix, so the update is released",
      "matchManagers": ["cargo"],
      "matchDepTypes": ["dependencies"],
      "semanticCommitType": "fix"
    },
    {
      "description": "Development-only crates: no release",
      "matchManagers": ["cargo"],
      "matchDepTypes": ["dev-dependencies", "build-dependencies"],
      "semanticCommitType": "chore"
    },
    {
      "description": "Swift packages that ship in the app: fix, so the update is released",
      "matchManagers": ["custom.regex"],
      "matchDepTypes": ["swift-package"],
      "semanticCommitType": "fix"
    },
    {
      "description": "GitHub Actions: no release",
      "matchManagers": ["github-actions"],
      "semanticCommitType": "ci"
    },
    {
      "description": "Tools pinned in mise.toml: no release",
      "matchManagers": ["mise"],
      "semanticCommitType": "chore"
    },
    {
      "description": "core/Cargo.lock refreshes change what ships: fix, so the update is released",
      "matchUpdateTypes": ["lockFileMaintenance"],
      "semanticCommitType": "fix"
    },
    {
      "description": "The LiveSplit crates, pinned to one git rev: grouped, labelled and prioritised",
      "matchManagers": ["cargo"],
      "matchDepNames": ["livesplit-*"],
      "groupName": "LiveSplit crates",
      "addLabels": ["livesplit"],
      "prPriority": 10,
      "semanticCommitType": "fix"
    }
  ]
}
```

- [ ] **Step 3: Validate the configuration**

Run: `mise x node@lts -- npx --yes --package renovate -- renovate-config-validator --strict renovate.json`
Expected: `Config validated successfully` and exit code 0.

- [ ] **Step 4: Document dependency updates**

In `CONTRIBUTING.md`, add after "Pull requests" (if issue #2 didn't already):

```markdown
## Dependency updates

[Renovate](https://docs.renovatebot.com/) opens pull requests every week to
update dependencies, configured in `renovate.json`. Their titles follow the
conventions above, and the type decides whether the update is released:

- `fix(deps)`: what ships in the app: crates, including the LiveSplit crates
  (one pull request moves both to the same livesplit-core revision), Swift
  packages in `project.yml`, and `core/Cargo.lock` refreshes. These produce a
  release.
- `ci(deps)`: GitHub Actions. No release.
- `chore(deps)`: tools pinned in `mise.toml` and development-only crates. No
  release.

Renovate's pull requests are the one exception to the linked-issue rule. They
go through the same checks and are merged by a maintainer like any other pull
request. The Dependency Dashboard issue lists pending updates.
```

In spec §15, add to the Renovate bullet: "Swift packages are declared in `project.yml`, which Renovate's Swift manager doesn't read, so a regex custom manager reads them."

- [ ] **Step 5: Commit, push and open the pull request**

```bash
git add renovate.json CONTRIBUTING.md docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md
git commit -m "ci: add Renovate configuration"
git push -u origin ci/renovate
gh pr create --base main --title "ci: add Renovate configuration" --body-file "$PR_BODY"
gh pr checks --watch
```

Expected: all required checks pass.

Stop here. The maintainer merges.

- [ ] **Step 6 (maintainer, after the merge): Install the Renovate app**

Install the Mend Renovate app from https://github.com/apps/renovate, selecting only `alexcosta97/livesplit-one-macos`.

- [ ] **Step 7 (coordinator): Verify Renovate works**

1. No `Configure Renovate` onboarding pull request: `gh pr list --search "Configure Renovate"` returns nothing.
2. The Dependency Dashboard issue appears: `gh issue list --search "Dependency Dashboard"`. It lists `livesplit-core` and `livesplit-core-capi` under one "LiveSplit crates" group, the GitHub Actions and the mise tools.
3. When the first Renovate pull requests open, their titles use the types from Step 2, they carry `dependencies` (and `livesplit` for the LiveSplit group), and all required checks pass.
