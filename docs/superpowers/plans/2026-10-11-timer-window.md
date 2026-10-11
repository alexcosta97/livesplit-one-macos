# Timer Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty window with the timer: a borderless window that draws livesplit-core's default layout and a new run with the software renderer on each display refresh, redrawing only when something changed, at the window's backing scale. The window can be moved by dragging and resized from its edges, its frame is remembered, it follows the renderer's size hint, Always on Top is applied, and overlay notices appear over the bottom (issue #11).

**Architecture:** `core/` gains a renderer (`core/src/render.rs`) that wraps livesplit-core's `BorrowedRenderer`. It skips a frame when the layout state, encoded as JSON, and the image size are the same as last time, and it returns the size hint that the C API's `SoftwareRenderer_render` discards. `LiveSplitCore/Wrapper/LayoutRenderer.swift` owns the pixel buffer and turns each drawn frame into a `CGImage`. In the app, `TimerContent` holds the `SharedTimer`, the layout and its state, and `TimerView` renders on each `CADisplayLink` tick and sets the image as its layer's contents. `TimerWindow` is a borderless, resizable `NSWindow`. `TimerWindowController` places the window (`WindowPlacement`), saves its frame through `SettingsStore`, applies the size hint, and shows `NoticeQueue`'s notices in a `NoticeView`.

**Tech Stack:** Rust (livesplit-core at the pinned revision, serde_json), Swift 6, AppKit (`NSWindow`, `NSView`, `CADisplayLink`), Core Graphics, Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md`, sections 5.1–5.3, 6, 10, 11, 14 and 16.2. Issue: #11, with its comments (the size hint, the link check, the `EventSink` callback rules, and the notes from #49).

**Branch and worktree:** `feat/timer-window`, at `../livesplit-one-macos-wt/timer-window`. **PR title:** `feat: draw the layout in a borderless timer window`. **PR body:** `Closes #11`, using the pull request template. One pull request for the whole plan; each task is one commit.

## Before you start

- **#25 (the wiki) is merged before Task 9.** Task 9 writes a wiki page in `docs/wiki/`, which #25 creates. Tasks 1–8 don't depend on it, so they can start before it merges. Rebase on `main` before Task 9.
- Read `CONTRIBUTING.md`, the spec sections above, and the comments on #11. Run the checks in `CONTRIBUTING.md` step 4 on `main` once.
- Read `LiveSplitCore/Wrapper/EventSink.swift`, `App/Config/Settings.swift`, `App/Config/SettingsStore.swift`, `App/AppDelegate.swift`, `Tests/E2E/E2EApp.swift` and `Tests/Integration/EventSinkTests.swift`. This plan builds on them.
- Shell setup on the maintainer's Mac: `export PATH="$(brew --prefix rustup)/bin:$HOME/.cargo/bin:$PATH"`, then `mise install`.
- After adding Swift files or changing `project.yml`, run `xcodegen generate`.
- Run one suite with `xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:<Target>/<SuiteName>`, where `<Target>` is `LiveSplitOneUnitTests`, `LiveSplitOneHeadlessUITests`, `LiveSplitOneIntegrationTests` or `LiveSplitOneE2ETests`.
- livesplit-core's source at the pinned revision is in `~/.cargo/git/checkouts/livesplit-core-*/61070c4/` after one build. The facts below come from it: `src/rendering/software.rs` (`BorrowedRenderer::render`), `src/rendering/mod.rs` (`render_vertical`, the size hint) and `capi/src/software_renderer.rs`.

## Global Constraints

- Swift never reimplements timer or rendering rules: livesplit-core does the timing, the layout state and the drawing (spec §4).
- The timer's read lock is held only while updating the layout state, never while drawing (spec §5.1). Nothing in this plan takes the write lock.
- Every frame is drawn at the window's backing scale: the buffer's size in pixels is `convertToBacking(bounds).size` (spec §5.2).
- Idle means no drawing: when neither the layout state nor the size changed, nothing is drawn, no `CGImage` is made and the layer isn't touched (spec §5.2).
- A new layout starts at **300 × 500 points**, LiveSplit One's default (`DEFAULT_LAYOUT_WIDTH` and `DEFAULT_LAYOUT_HEIGHT` in LiveSplitOne's `src/storage/index.ts`). When the renderer returns a size hint, the window takes that size and keeps its top-left corner, as LiveSplit One's `onResize` does.
- The default run is LiveSplit One's: one segment named **Time** (`getDefaultRun` in LiveSplitOne's `src/ui/LiveSplit.tsx`; `Label.NewSegmentName` is "Time" in English). The app's own text is English, so the name is always "Time".
- The layout's language follows macOS's first preferred language, through `Lang.parseLocale`, as LiveSplit One follows the browser's (`Lang.parseLocale(navigator.language)` in its `src/localization/index.ts`).
- Window frames are saved through `SettingsStore.update`, when a move or resize ends, never on every step. A frame that changes nothing doesn't write the file (`SettingsStore` already skips it).
- Overlay notices last **4 seconds** each, are drawn over the bottom of the timer, and are never part of the layout (spec §6).
- `EventSink`'s callback rules on #11 apply to any code that runs commands. This issue runs none; #13 and #14 do.
- Accessibility identifiers: `timer-window` (the window, already used by E2E tests), `timer-layout` (the view showing the layout), `overlay-notice` (the notice's text).
- Swift is formatted with `swift format` using `.swift-format` (4 spaces, 100 columns) and must pass `swift format lint --strict`. The code in this plan is close to that format but not checked against it: run `swift format --in-place --recursive App Tests LiveSplitCore/Wrapper` before each lint, and commit what it changes. Rust passes `cargo fmt --check` and `cargo clippy --all-targets --locked -- -D warnings`.
- Commits: Conventional Commits, signed, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A saved frame that is no longer on a screen** (a display unplugged, a resolution change, a hand-edited `app.toml`): the window opens centred on the main screen at 300 × 500, not off screen where it can't be dragged back, since it has no title bar. Needs at least 40 × 40 points on one screen's visible frame. Tests in Task 4.
2. **A zero or huge size** (the window minimised, a view not yet laid out, a hand-edited frame of 100000 points): nothing is drawn and nothing crashes. A panic in Rust across `extern "C"` aborts the app, so `core/` checks the sizes before livesplit-core sees them. Tests in Tasks 1 and 2.
3. **Notices arriving together** (a broken `app.toml` at launch, then a missing file from #12, then "Connected" from #14): each one shows for its 4 seconds in order, none is lost, and one already shown or waiting isn't queued twice. Tests in Task 5.
4. **Moving the window by dragging it:** a drag writes `app.toml` once after the window stops, not on every step, and the next launch opens the window where it was. Tests in Tasks 7 and 8.
5. **Retina and a window moved between a Retina and a non-Retina screen:** the frame is redrawn at the new backing scale (the size in pixels changes, so the renderer draws everything), and text stays sharp. Snapshot test at 2× in Task 2; checked by hand in Task 9.

## Spec changes this pull request makes

List each in the pull request description:

- §5.2: how the renderer skips unchanged frames, the layout's language, and the window's first size (300 × 500) and how it follows the size hint (Task 7).
- §5.3: the renderer that skips unchanged frames and returns the size hint (Task 1).
- §6: the default run, a saved frame that isn't on a screen, notices shown one after another, and the default layout's frame (Task 7).
- §11: the `default_layout_window` key (Task 3).
- §14.1: the snapshot tests' reference images and how to record them (Task 2). `CONTRIBUTING.md` says how to record them too.

## Left to later issues

Post each as a comment on the issue named once the pull request is open, and list it in the pull request description:

- **#12:** nothing opens a layout yet. `TimerWindowController.layoutPath` is `private(set)` with no setter, and `TimerContent.layout` (with the `LayoutState` made from it) is a `let`. #12 adds a way to open one, such as `setLayout(path:)` on the controller and a replaceable layout and state in `TimerContent`, which must:
  - call `saveFrameIfPending()` before switching `layoutPath`, so a pending save isn't written under the new layout's path;
  - set `layoutPath` to the layout's `url.standardizedFileURL.path`, then restore the window's frame from `settings.settings.frame(forLayout: path)` through `WindowPlacement.restoredFrame`;
  - ignore the next size hint when the layout has a saved frame. `fitLayout(_:)` applies every hint today, and the renderer keeps its cached height across a layout change, so the next frame gives the new layout's hint. Only a layout opened for the first time takes it;
  - call `content.markChanged()` after replacing the layout or the run, so the next frame shows it, and `imageCache.collect()` in `TimerContent`, so images from the old ones are freed;
  - show "couldn't be reopened" notices with `notices.show(_:)`.
- **#13:** menu commands call `content.markChanged()` after running, on the main actor, so the window shows the change at once. `AppDelegate.toggleAlwaysOnTop(_:)` exists: the menu items send it, and show a tick from `settings.settings.alwaysOnTop`. `TimerWindow` can become key, so keyboard shortcuts reach it. The right-click menu goes on `TimerView` (`timerView.menu`, or `menu(for:)`).
- **#14:** run server commands through an `EventSink` built on `TimerContent.timer`. Its `report` callback runs on any thread: hop with `DispatchQueue.main.async { content.markChanged() }`, never `sync`, since a report must return promptly (the callback rules on #11). Show connection notices with `TimerWindowController.notices.show(_:)`.
- **#18:** `E2EApp.relaunch()` and `E2EApp.settingsText(containing:)` are added (Task 8). The first-launch flow from spec §14.3 is covered by `TimerWindowTests.testFirstLaunchShowsTheDefaultLayout`.

---

### Task 1: `core/`: a renderer that skips unchanged frames and returns the size hint

**Files:**
- Create: `core/src/render.rs`
- Modify: `core/src/lib.rs`
- Modify: `core/src/ffi.rs`
- Modify: `core/Cargo.toml`, `core/Cargo.lock` (serde_json)
- Modify: `LiveSplitCore/CLiveSplitCore/include/lso_core.h`
- Modify: `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (§5.3)

**Interfaces:**
- Consumes: livesplit-core's `rendering::software::BorrowedRenderer`, `layout::LayoutState` (which implements `Serialize`), `settings::ImageCache`; `crate::sink::tests::timer` in tests.
- Produces:
  - Rust: `pub struct Renderer` with `new()`, `Default`, and `render(&mut self, state: &LayoutState, image_cache: &ImageCache, image: &mut [u8], size: [u32; 2], stride: u32) -> Rendered`; `pub struct Rendered { pub drew: bool, pub size_hint: Option<[f32; 2]> }`.
  - C: `LsoRendered { bool drew; bool has_size_hint; float size_hint_width; float size_hint_height; }`, `void *LsoRenderer_new(void)`, `void LsoRenderer_drop(void *self)`, `LsoRendered LsoRenderer_render(void *self, void const *layout_state, void const *image_cache, uint8_t *data, uint32_t width, uint32_t height, uint32_t stride)`. Task 2 calls them from Swift.

Key facts:
- `BorrowedRenderer::render` returns `Option<[f32; 2]>`: the layout's new size in the units of the resolution it was given (pixels here), returned only when the layout's total height changed since the last render (`render_vertical` in `src/rendering/mod.rs`). The first render caches the height and returns `None`.
- It only redraws the parts of the image that changed, so it must get the same buffer every frame, unless `force_redraw` is set.
- `PixmapMut::from_bytes(image, stride, height).unwrap()` panics on a zero size. A panic inside an `extern "C"` function aborts the app, so zero sizes never reach it.
- livesplit-core's `LayoutState` has no `PartialEq` and no `Clone`, but it implements `Serialize` (the C API's `Layout_update_state_as_json` uses it). Comparing its JSON with the last frame's is how a frame is skipped. serde_json 1.0.151 is already in `core/Cargo.lock` through livesplit-core.

- [ ] **Step 1: Add serde_json**

In `core/Cargo.toml`, under `[dependencies]`, after `futures-executor`:

```toml
# Compares each frame's layout state with the last one's (src/render.rs).
serde_json = "1.0.151"
```

Run: `cargo check --manifest-path core/Cargo.toml`
Expected: it builds, and `git diff core/Cargo.lock` shows only `"serde_json",` added to `lso-core`'s dependencies.

- [ ] **Step 2: Write the failing tests**

Create `core/src/render.rs` with only the tests for now:

```rust
//! Rendering that skips frames when nothing changed, and passes on
//! livesplit-core's size hint (spec §5.2, §5.3). The C API's
//! `SoftwareRenderer_render` draws every frame and discards the hint.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sink::tests::timer;
    use livesplit_core::{Lang, Layout, SharedTimer, component::BlankSpace};
    use std::{thread, time::Duration};

    const WIDTH: u32 = 300;
    const HEIGHT: u32 = 500;

    fn image(width: u32, height: u32) -> Vec<u8> {
        vec![0; width as usize * height as usize * 4]
    }

    fn state(layout: &mut Layout, cache: &mut ImageCache, timer: &SharedTimer) -> LayoutState {
        layout.state(cache, &timer.read().unwrap().snapshot(), Lang::English)
    }

    #[test]
    fn draws_the_first_frame() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);

        let state = state(&mut layout, &mut cache, &timer);
        let rendered = renderer.render(&state, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        assert_eq!(rendered, Rendered { drew: true, size_hint: None });
        assert!(pixels.iter().any(|&byte| byte != 0));
    }

    #[test]
    fn skips_a_frame_when_nothing_changed() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);
        let first = state(&mut layout, &mut cache, &timer);
        renderer.render(&first, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);
        let drawn = pixels.clone();

        let second = state(&mut layout, &mut cache, &timer);
        let rendered = renderer.render(&second, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        assert_eq!(rendered, Rendered { drew: false, size_hint: None });
        assert_eq!(pixels, drawn);
    }

    #[test]
    fn draws_again_when_the_size_changes() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let state = state(&mut layout, &mut cache, &timer);
        renderer.render(&state, &cache, &mut image(WIDTH, HEIGHT), [WIDTH, HEIGHT], WIDTH);

        let mut larger = image(2 * WIDTH, 2 * HEIGHT);
        let rendered =
            renderer.render(&state, &cache, &mut larger, [2 * WIDTH, 2 * HEIGHT], 2 * WIDTH);

        assert!(rendered.drew);
        assert!(larger.iter().any(|&byte| byte != 0));
    }

    #[test]
    fn draws_again_when_the_timer_moves() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);
        let before = state(&mut layout, &mut cache, &timer);
        renderer.render(&before, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        let _ = timer.write().unwrap().start();
        thread::sleep(Duration::from_millis(20));
        let after = state(&mut layout, &mut cache, &timer);

        assert!(renderer.render(&after, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH).drew);
    }

    #[test]
    fn returns_the_size_hint_when_the_layout_gets_taller() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);
        let before = state(&mut layout, &mut cache, &timer);
        renderer.render(&before, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        layout.push(BlankSpace::new());
        let after = state(&mut layout, &mut cache, &timer);
        let rendered = renderer.render(&after, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        let [width, height] = rendered.size_hint.expect("a taller layout gives a hint");
        assert_eq!(width, WIDTH as f32);
        assert!(height > HEIGHT as f32, "{height}");
    }

    #[test]
    fn a_zero_size_or_short_image_draws_nothing() {
        let (mut layout, mut cache, timer) =
            (Layout::default_layout(Lang::English), ImageCache::new(), timer(&["Time"]));
        let mut renderer = Renderer::new();
        let state = state(&mut layout, &mut cache, &timer);
        let nothing = Rendered { drew: false, size_hint: None };

        assert_eq!(renderer.render(&state, &cache, &mut [], [0, 0], 0), nothing);
        assert_eq!(renderer.render(&state, &cache, &mut [], [WIDTH, 0], WIDTH), nothing);
        let mut short = image(WIDTH, HEIGHT - 1);
        assert_eq!(
            renderer.render(&state, &cache, &mut short, [WIDTH, HEIGHT], WIDTH),
            nothing
        );
        let mut pixels = image(WIDTH, HEIGHT);
        assert_eq!(
            renderer.render(&state, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH - 1),
            nothing
        );
    }
}
```

Add `pub mod render;` to `core/src/lib.rs`, between `protocol` and `sink`.

- [ ] **Step 3: Run the tests to check they fail**

Run: `cargo test --manifest-path core/Cargo.toml render`
Expected: compile errors: `Renderer`, `Rendered`, `LayoutState` and `ImageCache` aren't found.

- [ ] **Step 4: Write the renderer**

In `core/src/render.rs`, between the module comment and the tests:

```rust
use std::mem;

use livesplit_core::{
    layout::LayoutState, rendering::software::BorrowedRenderer, settings::ImageCache,
};

/// What [`Renderer::render`] did.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct Rendered {
    /// Whether the image was drawn. If not, it still holds the last frame.
    pub drew: bool,
    /// livesplit-core's size hint: the layout's new natural size, in pixels,
    /// after its height changed.
    pub size_hint: Option<[f32; 2]>,
}

impl Rendered {
    const NOTHING: Self = Self {
        drew: false,
        size_hint: None,
    };
}

/// livesplit-core's software renderer, drawing only when the layout state or
/// the image's size changed since the last frame.
pub struct Renderer {
    inner: BorrowedRenderer,
    /// The last frame's state, encoded as JSON.
    last_state: Vec<u8>,
    /// Each frame's encoding, kept to reuse its memory.
    next_state: Vec<u8>,
    /// The last frame's width, height and stride.
    last_size: Option<[u32; 3]>,
}

impl Default for Renderer {
    fn default() -> Self {
        Self::new()
    }
}

impl Renderer {
    /// Creates a renderer that hasn't drawn anything yet.
    pub fn new() -> Self {
        Self {
            inner: BorrowedRenderer::new(),
            last_state: Vec::new(),
            next_state: Vec::new(),
            last_size: None,
        }
    }

    /// Renders `state` into `image` (RGBA8, premultiplied alpha, `stride`
    /// pixels a row), unless neither the state nor the size changed since the
    /// last call. Pass the same image every time, unless the size changes:
    /// livesplit-core only redraws the parts that changed. A zero size, a
    /// stride narrower than the width, or an image too short draws nothing.
    pub fn render(
        &mut self,
        state: &LayoutState,
        image_cache: &ImageCache,
        image: &mut [u8],
        [width, height]: [u32; 2],
        stride: u32,
    ) -> Rendered {
        let needed = stride as usize * height as usize * 4;
        if width == 0 || height == 0 || stride < width || image.len() < needed {
            return Rendered::NOTHING;
        }
        let size = [width, height, stride];

        self.next_state.clear();
        // A state that can't be encoded is drawn every time, never skipped.
        let encoded = serde_json::to_writer(&mut self.next_state, state).is_ok();
        let same_size = self.last_size == Some(size);
        if encoded && same_size && self.next_state == self.last_state {
            return Rendered::NOTHING;
        }

        // A new size comes with a new image, so every pixel is drawn.
        let size_hint = self.inner.render(
            state,
            image_cache,
            &mut image[..needed],
            [width, height],
            stride,
            !same_size,
        );
        if encoded {
            mem::swap(&mut self.last_state, &mut self.next_state);
        } else {
            self.last_state.clear();
        }
        self.last_size = Some(size);
        Rendered {
            drew: true,
            size_hint,
        }
    }
}
```

- [ ] **Step 5: Run the tests to check they pass**

Run: `cargo test --manifest-path core/Cargo.toml render`
Expected: 6 tests pass.

- [ ] **Step 6: Write the failing test for the C functions**

In `core/src/ffi.rs`'s `tests` module, add:

```rust
    #[test]
    fn renders_through_the_c_functions() {
        use livesplit_core::{Lang, Layout, settings::ImageCache};

        let mut layout = Layout::default_layout(Lang::English);
        let mut cache = ImageCache::new();
        let state = layout.state(
            &mut cache,
            &timer(&["Time"]).read().unwrap().snapshot(),
            Lang::English,
        );
        let mut renderer = LsoRenderer_new();
        let mut pixels = vec![0u8; 300 * 500 * 4];

        // SAFETY: valid objects, and a buffer of 300 * 500 * 4 bytes.
        let first = unsafe {
            LsoRenderer_render(&mut renderer, &state, &cache, pixels.as_mut_ptr(), 300, 500, 300)
        };
        // SAFETY: as above.
        let second = unsafe {
            LsoRenderer_render(&mut renderer, &state, &cache, pixels.as_mut_ptr(), 300, 500, 300)
        };
        // SAFETY: a null buffer is allowed and draws nothing.
        let null = unsafe {
            LsoRenderer_render(&mut renderer, &state, &cache, std::ptr::null_mut(), 300, 500, 300)
        };

        assert!(first.drew && !first.has_size_hint);
        assert!(!second.drew);
        assert!(!null.drew);
        LsoRenderer_drop(renderer);
    }
```

Run: `cargo test --manifest-path core/Cargo.toml ffi`
Expected: compile errors: `LsoRenderer_new`, `LsoRenderer_render` and `LsoRenderer_drop` aren't found.

- [ ] **Step 7: Write the C functions**

In `core/src/ffi.rs`, add to the `use` lines:

```rust
use livesplit_core::{layout::LayoutState, settings::ImageCache};

use crate::render::{Rendered, Renderer};
```

(merge them with the existing `use livesplit_core::…` and `use crate::{…}` lines), and before `#[cfg(test)]`:

```rust
/// What `LsoRenderer_render` did. The hint's width and height are 0 without
/// a hint.
#[repr(C)]
pub struct LsoRendered {
    pub drew: bool,
    pub has_size_hint: bool,
    pub size_hint_width: f32,
    pub size_hint_height: f32,
}

/// Creates a renderer that skips unchanged frames (spec §5.3).
#[unsafe(no_mangle)]
pub extern "C" fn LsoRenderer_new() -> Box<Renderer> {
    Box::default()
}

/// Drops the renderer. `this` must be a valid renderer.
#[unsafe(no_mangle)]
pub extern "C" fn LsoRenderer_drop(this: Box<Renderer>) {
    drop(this);
}

/// Renders the layout state into `data` (RGBA8, premultiplied alpha,
/// `stride` pixels a row), unless neither the state nor the size changed
/// since the last call. A null `data`, or a zero size, draws nothing.
///
/// # Safety
/// `this`, `layout_state` and `image_cache` are valid, and `data` is null or
/// valid for `stride * height * 4` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn LsoRenderer_render(
    this: &mut Renderer,
    layout_state: &LayoutState,
    image_cache: &ImageCache,
    data: *mut u8,
    width: u32,
    height: u32,
    stride: u32,
) -> LsoRendered {
    let rendered = if data.is_null() {
        Rendered {
            drew: false,
            size_hint: None,
        }
    } else {
        let len = stride as usize * height as usize * 4;
        // SAFETY: the caller passes `len` valid bytes.
        let image = unsafe { std::slice::from_raw_parts_mut(data, len) };
        this.render(layout_state, image_cache, image, [width, height], stride)
    };
    let [size_hint_width, size_hint_height] = rendered.size_hint.unwrap_or_default();
    LsoRendered {
        drew: rendered.drew,
        has_size_hint: rendered.size_hint.is_some(),
        size_hint_width,
        size_hint_height,
    }
}
```

- [ ] **Step 8: Declare them in the header**

In `LiveSplitCore/CLiveSplitCore/include/lso_core.h`, add `#include <stdbool.h>` after `#include <stdint.h>`, and before `#ifdef __cplusplus` at the end:

```c
/// What `LsoRenderer_render` did.
typedef struct LsoRendered {
    /// Whether the image was drawn. If not, it still holds the last frame.
    bool drew;
    /// Whether the layout's height changed, giving it a new natural size.
    bool has_size_hint;
    /// The natural size in pixels, when `has_size_hint`; otherwise 0.
    float size_hint_width;
    float size_hint_height;
} LsoRendered;

/// Creates a renderer that draws only when the layout state or the size changed.
void *LsoRenderer_new(void);
/// Drops the renderer. `self` must be a valid, non-null renderer.
void LsoRenderer_drop(void *self);
/// Renders a `LayoutState` into `data` (RGBA8, premultiplied alpha, `stride` pixels a row)
/// unless neither the state nor the size changed since the last call. Pass the same buffer
/// every time unless the size changes. `self`, `layout_state` and `image_cache` must be valid
/// and non-null. `data` may be NULL, which draws nothing, or valid for `stride * height * 4`
/// bytes.
LsoRendered LsoRenderer_render(void *self, void const *layout_state, void const *image_cache,
                               uint8_t *data, uint32_t width, uint32_t height, uint32_t stride);
```

- [ ] **Step 9: Run every Rust check**

```bash
cargo fmt --check --manifest-path core/Cargo.toml
cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
cargo test --locked --manifest-path core/Cargo.toml
```

Expected: all pass. If `cargo fmt --check` fails, run `cargo fmt --manifest-path core/Cargo.toml` and check the diff is only formatting.

- [ ] **Step 10: Update spec §5.3**

In §5.3, after the `encode_event` bullet, add:

```markdown
- **Rendering that skips unchanged frames.** `LsoRenderer_render` wraps
  livesplit-core's `BorrowedRenderer`. It compares the layout state, encoded
  as JSON, and the image's size with the last frame's, and draws only when
  one of them changed. It also returns the renderer's size hint, which the C
  API's `SoftwareRenderer_render` discards.
```

- [ ] **Step 11: Commit**

```bash
git add core/ LiveSplitCore/CLiveSplitCore/include/lso_core.h docs/superpowers/specs/
git commit -m "feat(core): render only changed frames and return the size hint"
```

(End the message with the `Co-Authored-By` line from Global Constraints, as every commit in this plan does.)

---

### Task 2: `LayoutRenderer` in Swift, and snapshot tests of the default layout

**Files:**
- Create: `LiveSplitCore/Wrapper/LayoutRenderer.swift`
- Create: `Tests/Integration/RenderingTests.swift`
- Create: `Tests/Integration/Support/Snapshot.swift`
- Create: `Tests/Integration/Snapshots/default-layout.png`, `default-layout-2x.png`, `three-segments.png` (recorded in Step 5)
- Modify: `CONTRIBUTING.md` (Testing)
- Modify: `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (§14.1)

**Interfaces:**
- Consumes: the C functions from Task 1; the generated `Layout`, `LayoutState`, `ImageCache`, `Run`, `Segment`, `Timer`, `SharedTimer`, `BlankSpaceComponent`, `Lang`; `EventSink`.
- Produces:
  - `public struct RenderedFrame { public let image: CGImage?; public let sizeHint: CGSize? }`: `image` is `nil` when nothing was drawn.
  - `public final class LayoutRenderer { public init(); public func render(_ state: LayoutStateRef, _ imageCache: ImageCacheRef, width: Int, height: Int) -> RenderedFrame; public static let maximumSide: Int }`. Used on one thread (the main thread, in the app).

Key facts:
- The generated classes keep their pointer in `var ptr` with internal access. `LayoutRenderer` is in the same module (`LiveSplitCore`), so it can read `state.ptr`, as `EventSink` reads `timer.ptr`.
- tiny-skia's pixels are RGBA8 with premultiplied alpha, so the image is `premultipliedLast` in sRGB.
- The renderer keeps drawing into its buffer, so each `CGImage` gets its own copy of the bytes. Sharing the buffer would change an image Core Animation is still showing.
- livesplit-core draws with its own bundled fonts unless a layout names a custom one, so the default layout draws the same on every Mac. CI runs on Apple Silicon; the comparison allows small differences anyway.
- XcodeGen copies files it doesn't compile (the PNGs) into the test bundle's resources, flattened. `Bundle(for:)` finds them by name.
- `xcodebuild` passes environment variables starting with `TEST_RUNNER_` to the tests without the prefix, so `TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1` sets `LSO_RECORD_SNAPSHOTS=1` in the test process.

- [ ] **Step 1: Write the snapshot helper**

`Tests/Integration/Support/Snapshot.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class Marker {}

/// Compares rendered images with reference PNGs in `Tests/Integration/Snapshots/` (spec §14.1).
///
/// Run the tests with `TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1` to write new references instead of
/// comparing; each test then fails, so a recording is never mistaken for a pass.
enum Snapshot {
    /// How far one channel of a pixel may be from the reference.
    static let channelTolerance = 2
    /// The share of pixels that may differ by more than that.
    static let pixelTolerance = 0.001

    /// `nil` if `image` matches the reference `name`, otherwise why it doesn't.
    static func mismatch(_ image: CGImage, _ name: String) -> String? {
        if ProcessInfo.processInfo.environment["LSO_RECORD_SNAPSHOTS"] == "1" {
            // This file is Tests/Integration/Support/Snapshot.swift.
            let folder = URL(filePath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "Snapshots")
            let url = folder.appending(path: "\(name).png")
            return write(image, to: url)
                ? "Recorded \(url.path). Run again without recording to compare."
                : "Couldn't record \(url.path)."
        }
        guard let url = Bundle(for: Marker.self).url(forResource: name, withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let reference = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "No reference \(name).png. Record it (see CONTRIBUTING.md)." }
        guard reference.width == image.width, reference.height == image.height else {
            return "\(name): \(image.width)×\(image.height), reference "
                + "\(reference.width)×\(reference.height)."
        }
        guard let actual = pixels(of: image), let expected = pixels(of: reference) else {
            return "\(name): couldn't read the pixels."
        }
        var differing = 0
        for pixel in stride(from: 0, to: actual.count, by: 4) {
            let channels = (0..<4).map { abs(Int(actual[pixel + $0]) - Int(expected[pixel + $0])) }
            if channels.contains(where: { $0 > channelTolerance }) { differing += 1 }
        }
        let share = Double(differing) / Double(image.width * image.height)
        guard share > pixelTolerance else { return nil }
        let saved = FileManager.default.temporaryDirectory
            .appending(path: "lso-snapshots/\(name).png")
        try? FileManager.default.createDirectory(
            at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = write(image, to: saved)
        return "\(name): \(differing) pixels differ. This run's image is at \(saved.path)."
    }

    /// The image's pixels as RGBA8, premultiplied, in sRGB.
    static func pixels(of image: CGImage) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = data.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drew ? data : nil
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/Integration/RenderingTests.swift`:

```swift
import CoreGraphics
import Foundation
import LiveSplitCore
import Testing

/// A layout, a timer and the layout's state, as the timer window holds them.
private final class Scene {
    let layout = Layout.defaultLayout(Scene.english)
    let imageCache = ImageCache()
    let timer: SharedTimer
    let state: LayoutState

    static let english = Lang.parseLocale("en")

    init(segments: [String] = ["Time"]) {
        let run = Run()
        for name in segments { run.pushSegment(Segment(name)) }
        // `LiveSplitCore.Timer`, not Foundation's.
        timer = LiveSplitCore.Timer(run)!.intoShared()
        let lock = timer.read()
        state = layout.state(imageCache, lock.timer(), Self.english)
        lock.dispose()
    }

    /// Updates the state from the timer, as each display refresh does.
    func update() {
        let lock = timer.read()
        layout.updateState(state, imageCache, lock.timer(), Self.english)
        lock.dispose()
    }
}

@Suite struct RenderingTests {
    @Test func theDefaultLayoutMatchesItsSnapshot() throws {
        let scene = Scene()
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 300, height: 500)
        let image = try #require(frame.image)
        #expect(Snapshot.mismatch(image, "default-layout") == nil)
    }

    @Test func theDefaultLayoutAtTwiceTheScaleMatchesItsSnapshot() throws {
        let scene = Scene()
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 600, height: 1000)
        let image = try #require(frame.image)
        #expect(image.width == 600 && image.height == 1000)
        #expect(Snapshot.mismatch(image, "default-layout-2x") == nil)
    }

    @Test func aRunWithSegmentsMatchesItsSnapshot() throws {
        let scene = Scene(segments: ["Forest", "Castle", "Final Boss"])
        let frame = LayoutRenderer().render(scene.state, scene.imageCache, width: 300, height: 500)
        let image = try #require(frame.image)
        #expect(Snapshot.mismatch(image, "three-segments") == nil)
    }

    @Test func anIdleTimerDrawsNothingNew() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        #expect(renderer.render(scene.state, scene.imageCache, width: 300, height: 500).image != nil)

        scene.update()
        let again = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)

        #expect(again.image == nil)
        #expect(again.sizeHint == nil)
    }

    @Test func aRunningTimerDrawsAgain() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        _ = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)
        let sink = EventSink(timer: scene.timer, report: { _ in }, decideReset: { .cancel })
        #expect(sink.handleCommand(#"{"command":"start"}"#) == #"{"success":null}"#)
        Thread.sleep(forTimeInterval: 0.02)

        scene.update()

        #expect(renderer.render(scene.state, scene.imageCache, width: 300, height: 500).image != nil)
    }

    @Test func aTallerLayoutGivesASizeHint() throws {
        let scene = Scene()
        let renderer = LayoutRenderer()
        _ = renderer.render(scene.state, scene.imageCache, width: 300, height: 500)

        scene.layout.push(BlankSpaceComponent().intoGeneric())
        scene.update()
        let hint = try #require(
            renderer.render(scene.state, scene.imageCache, width: 300, height: 500).sizeHint)

        #expect(hint.width == 300)
        #expect(hint.height > 500)
    }

    @Test func aZeroOrHugeSizeDrawsNothing() {
        let scene = Scene()
        let renderer = LayoutRenderer()
        let side = LayoutRenderer.maximumSide
        #expect(renderer.render(scene.state, scene.imageCache, width: 0, height: 500).image == nil)
        #expect(renderer.render(scene.state, scene.imageCache, width: 300, height: -1).image == nil)
        #expect(
            renderer.render(scene.state, scene.imageCache, width: side + 1, height: 10).image
                == nil)
    }
}
```

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneIntegrationTests/RenderingTests`
Expected: build fails: `LayoutRenderer` and `RenderedFrame` aren't found.

- [ ] **Step 3: Write `LayoutRenderer`**

`LiveSplitCore/Wrapper/LayoutRenderer.swift`:

```swift
import CLiveSplitCore
import CoreGraphics
import Foundation

/// One frame from `LayoutRenderer`.
public struct RenderedFrame {
    /// The new image, or `nil` when nothing changed since the last frame.
    public let image: CGImage?
    /// The layout's natural size in pixels, after its height changed (spec §5.2).
    public let sizeHint: CGSize?

    static let nothing = RenderedFrame(image: nil, sizeHint: nil)
}

/// Draws a layout state with livesplit-core's software renderer, through core/'s renderer, which
/// skips frames when nothing changed (spec §5.2, §5.3). Not thread-safe: use one thread.
public final class LayoutRenderer {
    /// The largest width or height drawn, in pixels. Anything larger draws nothing, so a
    /// hand-edited window frame can't ask for gigabytes.
    public static let maximumSide = 16_384

    private let ptr: UnsafeMutableRawPointer
    /// The pixels livesplit-core draws into. The same buffer every frame, since it only redraws
    /// what changed; replaced, and drawn whole, when the size changes.
    private var buffer: [UInt8] = []
    private var width = 0
    private var height = 0

    public init() {
        ptr = LsoRenderer_new()
    }

    deinit {
        LsoRenderer_drop(ptr)
    }

    /// Renders `state` at `width` × `height` pixels, if it or the size changed since the last
    /// frame.
    public func render(_ state: LayoutStateRef, _ imageCache: ImageCacheRef, width: Int, height: Int)
        -> RenderedFrame
    {
        precondition(state.ptr != nil && imageCache.ptr != nil)
        guard (1...Self.maximumSide).contains(width), (1...Self.maximumSide).contains(height)
        else { return .nothing }
        if width != self.width || height != self.height {
            buffer = [UInt8](repeating: 0, count: width * height * 4)
            self.width = width
            self.height = height
        }
        let result = buffer.withUnsafeMutableBufferPointer { pixels in
            LsoRenderer_render(
                ptr, state.ptr, imageCache.ptr, pixels.baseAddress, UInt32(width), UInt32(height),
                UInt32(width))
        }
        let sizeHint =
            result.has_size_hint
            ? CGSize(
                width: CGFloat(result.size_hint_width), height: CGFloat(result.size_hint_height))
            : nil
        return RenderedFrame(image: result.drew ? makeImage() : nil, sizeHint: sizeHint)
    }

    /// A copy of the buffer as an image. A copy, because the next frame draws into the buffer
    /// while this image may still be on screen.
    private func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
```

- [ ] **Step 4: Run the tests other than the snapshots**

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneIntegrationTests/RenderingTests`
Expected: the four tests that aren't snapshots pass. The three snapshot tests fail with "No reference … Record it".

- [ ] **Step 5: Record the snapshots and look at them**

```bash
TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1 xcodebuild test -project LiveSplitOne.xcodeproj \
  -scheme LiveSplitOne -destination 'platform=macOS' \
  -only-testing:LiveSplitOneIntegrationTests/RenderingTests
open Tests/Integration/Snapshots/
```

Expected: the three snapshot tests fail with "Recorded …", and `Tests/Integration/Snapshots/` holds three PNGs. Open each one and check it by eye: the default layout has a title, a splits list with the segment names, a large timer at 0.00 and a "Previous Segment" row. Text in `default-layout-2x.png` is sharp at its full size, not a blown-up `default-layout.png`. If an image looks wrong, stop and find out why before going on.

- [ ] **Step 6: Run the tests again**

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneIntegrationTests/RenderingTests`
Expected: all 7 tests pass. (`xcodegen generate` again, so the new PNGs are copied into the bundle.)

- [ ] **Step 7: Document recording**

In `CONTRIBUTING.md`, at the end of the "Testing" section, add:

~~~markdown
### Snapshot tests

The integration tests compare rendered layouts with reference images in
`Tests/Integration/Snapshots/`. When a change is meant to change how a
layout looks (a livesplit-core update, for example), record new references,
look at each one, and commit them with the change:

```sh
TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1 xcodebuild test -project LiveSplitOne.xcodeproj \
  -scheme LiveSplitOne -destination 'platform=macOS' \
  -only-testing:LiveSplitOneIntegrationTests/RenderingTests
```

Recording makes each snapshot test fail, so a run that records is never
taken for a pass. Run the tests again without the variable to check. When a
comparison fails, the message names a file with that run's image.
~~~

In spec §14.1, in the Integration row, change "rendering of reference layouts compared with snapshots" to "rendering of reference layouts compared with reference images in `Tests/Integration/Snapshots/`, recorded with `TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1` and checked by eye".

- [ ] **Step 8: Commit**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
git add LiveSplitCore/Wrapper/LayoutRenderer.swift Tests/Integration CONTRIBUTING.md docs/superpowers/specs/
git commit -m "feat: draw layouts into images with LayoutRenderer"
```

---

### Task 3: The default layout's window frame in `app.toml`

**Files:**
- Modify: `App/Config/Settings.swift`
- Modify: `Tests/Unit/SettingsTests.swift`
- Modify: `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (§11)

**Interfaces:**
- Consumes: `Settings`, `WindowFrame`, `LayoutWindow`.
- Produces: `Settings.defaultLayoutFrame: WindowFrame?` (key `default_layout_window`); `Settings.frame(forLayout path: String?) -> WindowFrame?` and `Settings.setFrame(_ frame: WindowFrame, forLayout path: String?)`, where `nil` is the default layout; `WindowFrame: Codable` (keys `x`, `y`, `width`, `height`). Tasks 4 and 7 use them.

Key facts:
- The default layout has no file, so it has no path to key a `windows` entry with (#11's comment from #49). It gets its own table instead of a made-up path, so no path a user could have is ever taken.
- `WindowFrame`'s property names are already the TOML keys, so the synthesised `Codable` writes `x`, `y`, `width` and `height`. swift-toml reads whole numbers as `Double`, so `x = 100` loads.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/Unit/SettingsTests.swift`, inside the suite:

```swift
    @Test func theDefaultLayoutsFrameIsKeptApartFromLayoutFiles() throws {
        var settings = Settings()
        let frame = WindowFrame(x: 10, y: 20, width: 300, height: 500)
        settings.setFrame(frame, forLayout: nil)

        #expect(settings.frame(forLayout: nil) == frame)
        #expect(settings.windows.isEmpty)
        let text = try settings.tomlText()
        #expect(text.contains("[default_layout_window]"))
        #expect(try Settings.decode(Data(text.utf8)) == settings)
    }

    @Test func aWholeNumberDefaultLayoutFrameLoads() throws {
        let text = """
            [default_layout_window]
            x = 100
            y = 200
            width = 300
            height = 500
            """
        let settings = try Settings.decode(Data(text.utf8))
        #expect(settings.defaultLayoutFrame == WindowFrame(x: 100, y: 200, width: 300, height: 500))
    }

    @Test func anUnusableDefaultLayoutFrameIsDropped() throws {
        let text = """
            [default_layout_window]
            x = 0
            y = 0
            width = 0
            height = 500
            """
        #expect(try Settings.decode(Data(text.utf8)).defaultLayoutFrame == nil)
    }

    @Test func aLayoutPathStillKeysItsOwnFrame() {
        var settings = Settings()
        let frame = WindowFrame(x: 1, y: 2, width: 3, height: 4)
        settings.setFrame(frame, forLayout: "/Users/me/Layouts/main.ls1l")
        #expect(settings.frame(forLayout: "/Users/me/Layouts/main.ls1l") == frame)
        #expect(settings.frame(forLayout: nil) == nil)
    }
```

Run: `xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneUnitTests/SettingsTests`
Expected: build fails: `defaultLayoutFrame` isn't a member, and `nil` can't be passed as `forLayout`.

- [ ] **Step 2: Write the change**

In `App/Config/Settings.swift`:

1. After `var windows: [LayoutWindow] = []`, add:

```swift
    /// The window's frame for the default layout, which has no file (spec §6).
    var defaultLayoutFrame: WindowFrame?
```

2. Replace `frame(forLayout:)` and `setFrame(_:forLayout:)` with:

```swift
    /// The frame saved for the layout at `path`, or for the default layout when `path` is `nil`.
    func frame(forLayout path: String?) -> WindowFrame? {
        guard let path else { return defaultLayoutFrame }
        return windows.first { $0.layout == path }?.frame
    }

    /// Saves `frame` for the layout at `path`, or for the default layout when `path` is `nil`,
    /// replacing any frame saved for it.
    mutating func setFrame(_ frame: WindowFrame, forLayout path: String?) {
        guard let path else {
            defaultLayoutFrame = frame
            return
        }
        if let index = windows.firstIndex(where: { $0.layout == path }) {
            windows[index].frame = frame
        } else {
            windows.append(LayoutWindow(layout: path, frame: frame))
        }
    }
```

3. In `CodingKeys`, after `case windows`, add `case defaultLayoutFrame = "default_layout_window"`.

4. In `init(from:)`, after the `windows = …` statement, add:

```swift
        defaultLayoutFrame = try container.decodeIfPresent(
            WindowFrame.self, forKey: .defaultLayoutFrame
        ).flatMap { $0.isUsable ? $0 : nil }
```

5. In `encode(to:)`, after `try container.encode(windows, forKey: .windows)`, add `try container.encodeIfPresent(defaultLayoutFrame, forKey: .defaultLayoutFrame)`.

6. Change `struct WindowFrame: Equatable, Sendable {` to `struct WindowFrame: Codable, Equatable, Sendable {`.

- [ ] **Step 3: Run the tests**

Run: `xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneUnitTests/SettingsTests -only-testing:LiveSplitOneUnitTests/SettingsStoreTests`
Expected: all pass, the existing ones included.

- [ ] **Step 4: Update spec §11**

In §11's list of what `app.toml` holds, change "the window frame per layout path, and Always on Top;" to "the window frame per layout path, the default layout's window frame, and Always on Top;". In the example file, after the last `[[windows]]` table, add:

```toml
[default_layout_window]
x = 120.0
y = 300.0
width = 300.0
height = 500.0
```

and in the list of keys, add `default_layout_window` (a table with `x`, `y`, `width`, `height`): the window's frame while the default layout is shown, which has no path. If §11 names the keys differently from this, follow its form.

- [ ] **Step 5: Commit**

```bash
git add App/Config/Settings.swift Tests/Unit/SettingsTests.swift docs/superpowers/specs/
git commit -m "feat(settings): remember the default layout's window frame"
```

---

### Task 4: Where the window goes

**Files:**
- Create: `App/TimerWindow/WindowPlacement.swift`
- Create: `Tests/Unit/WindowPlacementTests.swift`

**Interfaces:**
- Consumes: `WindowFrame` (Task 3).
- Produces: `enum WindowPlacement` with `static let defaultSize: CGSize` (300 × 500), `static let minimumSize: CGSize` (40 × 20), `static let minimumVisible: CGFloat` (40), `static func restoredFrame(_ saved: WindowFrame?, screens: [CGRect]) -> CGRect?`, `static func centred(_ size: CGSize, on screen: CGRect) -> CGRect`, `static func resized(_ frame: CGRect, to size: CGSize) -> CGRect`, `static func size(forHint hint: CGSize, scale: CGFloat) -> CGSize?`, `static func windowFrame(_ rect: CGRect) -> WindowFrame`. Task 7 uses them all.

Key facts:
- AppKit's screen coordinates have their origin at the bottom left of the main screen, with y going up. "Keeping the top-left corner" means keeping `minX` and `maxY`.
- `NSScreen.visibleFrame` leaves out the menu bar and the Dock. The screens are passed in, so the tests need no screens.
- The hint is in pixels at the size the frame was rendered at, so points are pixels divided by the backing scale.

- [ ] **Step 1: Write the failing tests**

`Tests/Unit/WindowPlacementTests.swift`:

```swift
import CoreGraphics
import Testing

@testable import LiveSplitOne

@Suite struct WindowPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func aSavedFrameOnAScreenIsUsed() {
        let saved = WindowFrame(x: 100, y: 200, width: 250, height: 400)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen])
                == CGRect(x: 100, y: 200, width: 250, height: 400))
    }

    @Test func aSavedFrameOffEveryScreenIsIgnored() {
        let saved = WindowFrame(x: 3000, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == nil)
    }

    @Test func aSavedFrameBarelyOnAScreenIsIgnored() {
        // 30 points of it on the screen: too little to grab and drag back.
        let saved = WindowFrame(x: 1410, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == nil)
    }

    @Test func aSavedFrameOnASecondScreenIsUsed() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = WindowFrame(x: 2000, y: 100, width: 300, height: 500)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen, second]) != nil)
    }

    @Test func noSavedFrameOrNoScreensGivesNothing() {
        #expect(WindowPlacement.restoredFrame(nil, screens: [screen]) == nil)
        let saved = WindowFrame(x: 100, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: []) == nil)
    }

    @Test func aTinySavedFrameGrowsToTheMinimum() throws {
        let saved = WindowFrame(x: 100, y: 200, width: 1, height: 1)
        let frame = try #require(
            WindowPlacement.restoredFrame(saved, screens: [screen]))
        #expect(frame.size == WindowPlacement.minimumSize)
    }

    @Test func theDefaultSizeIsLiveSplitOnes() {
        #expect(WindowPlacement.defaultSize == CGSize(width: 300, height: 500))
    }

    @Test func centredIsInTheMiddleOfTheScreen() {
        let frame = WindowPlacement.centred(CGSize(width: 300, height: 500), on: screen)
        #expect(frame == CGRect(x: 570, y: 187.5, width: 300, height: 500))
    }

    @Test func resizingKeepsTheTopLeftCorner() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 500)
        let resized = WindowPlacement.resized(frame, to: CGSize(width: 300, height: 600))
        #expect(resized == CGRect(x: 100, y: 100, width: 300, height: 600))
        #expect(resized.minX == frame.minX && resized.maxY == frame.maxY)
    }

    @Test func aHintInPixelsBecomesPoints() {
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 600, height: 1200), scale: 2)
                == CGSize(width: 300, height: 600))
    }

    @Test func aHintThatIsntASizeIsIgnored() {
        #expect(WindowPlacement.size(forHint: CGSize(width: 0, height: 100), scale: 2) == nil)
        #expect(
            WindowPlacement.size(forHint: CGSize(width: .infinity, height: 100), scale: 2) == nil)
        #expect(WindowPlacement.size(forHint: CGSize(width: 300, height: 500), scale: 0) == nil)
    }

    @Test func aTinyHintGrowsToTheMinimum() {
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 10, height: 10), scale: 1)
                == WindowPlacement.minimumSize)
    }

    @Test func aRectBecomesAWindowFrame() {
        #expect(
            WindowPlacement.windowFrame(CGRect(x: 1, y: 2, width: 3, height: 4))
                == WindowFrame(x: 1, y: 2, width: 3, height: 4))
    }
}
```

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneUnitTests/WindowPlacementTests`
Expected: build fails: `WindowPlacement` isn't found.

- [ ] **Step 2: Write `WindowPlacement`**

`App/TimerWindow/WindowPlacement.swift`:

```swift
import CoreGraphics

/// Where the timer window goes and how big it is (spec §5.2, §6). Pure, so it's tested without
/// screens or windows.
enum WindowPlacement {
    /// LiveSplit One's size for a layout it hasn't sized yet, in points.
    static let defaultSize = CGSize(width: 300, height: 500)
    /// The smallest window, so it can't shrink to something that can't be grabbed.
    static let minimumSize = CGSize(width: 40, height: 20)
    /// How much of a saved frame, in both directions, must be on one screen for it to be used.
    /// A borderless window has no title bar to drag back from off screen.
    static let minimumVisible: CGFloat = 40

    /// The saved frame, at least `minimumSize`, if enough of it is on one of `screens` (their
    /// visible frames); otherwise `nil`.
    static func restoredFrame(_ saved: WindowFrame?, screens: [CGRect]) -> CGRect? {
        guard let saved, saved.isUsable else { return nil }
        let frame = CGRect(
            x: saved.x, y: saved.y, width: max(saved.width, minimumSize.width),
            height: max(saved.height, minimumSize.height))
        let onScreen = screens.contains { screen in
            let visible = screen.intersection(frame)
            return !visible.isNull && visible.width >= minimumVisible
                && visible.height >= minimumVisible
        }
        return onScreen ? frame : nil
    }

    /// A frame of `size` in the middle of `screen`.
    static func centred(_ size: CGSize, on screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// `frame` at `size`, keeping its top-left corner, so the layout grows downwards as in
    /// LiveSplit One.
    static func resized(_ frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// The window size in points for a size hint in pixels at `scale`, at least `minimumSize`,
    /// or `nil` if the hint or the scale isn't a positive, finite number.
    static func size(forHint hint: CGSize, scale: CGFloat) -> CGSize? {
        let values = [hint.width, hint.height, scale]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return CGSize(
            width: max(hint.width / scale, minimumSize.width),
            height: max(hint.height / scale, minimumSize.height))
    }

    /// `rect` as `app.toml` stores it.
    static func windowFrame(_ rect: CGRect) -> WindowFrame {
        WindowFrame(
            x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width),
            height: Double(rect.height))
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneUnitTests/WindowPlacementTests`
Expected: 13 tests pass.

- [ ] **Step 4: Commit**

```bash
git add App/TimerWindow/WindowPlacement.swift Tests/Unit/WindowPlacementTests.swift
git commit -m "feat: place the timer window from its saved frame"
```

---

### Task 5: Overlay notices

**Files:**
- Create: `App/TimerWindow/NoticeQueue.swift`
- Create: `App/TimerWindow/NoticeView.swift`
- Create: `App/TimerWindow/LaunchNotices.swift`
- Create: `Tests/Unit/NoticeQueueTests.swift`
- Create: `Tests/Unit/LaunchNoticesTests.swift`
- Create: `Tests/HeadlessUI/NoticeViewTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.LoadOutcome`.
- Produces:
  - `@MainActor final class NoticeQueue { typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void; static let duration: TimeInterval /* 4 */; init(schedule: @escaping Schedule = NoticeQueue.afterDelay); var onChange: ((String?) -> Void)?; private(set) var current: String?; var waiting: [String] { get }; func show(_ text: String) }`.
  - `@MainActor final class NoticeView: NSView { var text: String { get }; func show(_ text: String?); func place(in view: NSView) }`.
  - `enum LaunchNotices { static func settings(_ outcome: SettingsStore.LoadOutcome) -> String? }`.

Key facts:
- The settings texts are the ones suggested on #11 from #49. Task 9 puts them in the wiki word for word.
- The notice must not take clicks: a drag that starts on it still moves the window, so `hitTest` returns `nil`.
- A multi-line `NSTextField` under Auto Layout only wraps with `preferredMaxLayoutWidth` set, so `NoticeView` sets it from its superview's width on each layout.

- [ ] **Step 1: Write the failing tests**

`Tests/Unit/NoticeQueueTests.swift`:

```swift
import Foundation
import Testing

@testable import LiveSplitOne

/// Runs scheduled actions when the test says, instead of after a delay.
@MainActor
private final class ManualClock {
    private(set) var delays: [TimeInterval] = []
    private var actions: [@MainActor @Sendable () -> Void] = []

    var schedule: NoticeQueue.Schedule {
        { [self] delay, action in
            delays.append(delay)
            actions.append(action)
        }
    }

    /// Runs the oldest scheduled action, as if its delay had passed.
    func advance() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
}

@MainActor
@Suite struct NoticeQueueTests {
    @Test func aNoticeShowsForFourSeconds() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        var shown: [String?] = []
        queue.onChange = { shown.append($0) }

        queue.show("Connected to pc")
        #expect(queue.current == "Connected to pc")
        #expect(clock.delays == [4])

        clock.advance()
        #expect(queue.current == nil)
        #expect(shown == ["Connected to pc", nil])
    }

    @Test func noticesShowOneAfterAnother() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        var shown: [String?] = []
        queue.onChange = { shown.append($0) }

        queue.show("First")
        queue.show("Second")
        #expect(queue.current == "First")
        #expect(queue.waiting == ["Second"])

        clock.advance()
        #expect(queue.current == "Second")
        clock.advance()
        #expect(shown == ["First", "Second", nil])
        #expect(clock.delays == [4, 4])
    }

    @Test func aNoticeAlreadyShownOrWaitingIsntRepeated() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        queue.show("Lost connection")
        queue.show("Lost connection")
        queue.show("Other")
        queue.show("Other")
        #expect(queue.current == "Lost connection")
        #expect(queue.waiting == ["Other"])
    }

    @Test func theSameNoticeCanShowAgainLater() {
        let clock = ManualClock()
        let queue = NoticeQueue(schedule: clock.schedule)
        queue.show("Connected to pc")
        clock.advance()
        queue.show("Connected to pc")
        #expect(queue.current == "Connected to pc")
    }
}
```

`Tests/Unit/LaunchNoticesTests.swift`:

```swift
import Testing

@testable import LiveSplitOne

@Suite struct LaunchNoticesTests {
    @Test func readSettingsNeedNoNotice() {
        #expect(LaunchNotices.settings(.missing) == nil)
        #expect(LaunchNotices.settings(.loaded) == nil)
    }

    @Test func recoveredSettingsNameTheKeptFile() {
        #expect(
            LaunchNotices.settings(.recovered(reason: "line 3"))
                == "Couldn't read the settings, so the defaults are used. "
                + "The old file is app.toml.bad.")
    }

    @Test func unrecoverableSettingsSayChangesArentSaved() {
        #expect(
            LaunchNotices.settings(.unrecoverable(reason: "permission denied"))
                == "Couldn't read the settings, so the defaults are used and changes aren't saved."
        )
    }
}
```

`Tests/HeadlessUI/NoticeViewTests.swift`:

```swift
import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct NoticeViewTests {
    private func placed() -> (NoticeView, NSView) {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let notice = NoticeView()
        notice.place(in: parent)
        return (notice, parent)
    }

    @Test func itIsHiddenUntilANoticeShows() {
        let (notice, _) = placed()
        #expect(notice.isHidden)
    }

    @Test func itShowsTheTextForAccessibility() throws {
        let (notice, _) = placed()
        notice.show("Connected to pc")

        #expect(!notice.isHidden)
        #expect(notice.text == "Connected to pc")
        let label = try #require(
            notice.subviews.first { $0.accessibilityIdentifier() == "overlay-notice" })
        #expect((label as? NSTextField)?.stringValue == "Connected to pc")
    }

    @Test func showingNothingHidesIt() {
        let (notice, _) = placed()
        notice.show("Connected to pc")
        notice.show(nil)
        #expect(notice.isHidden)
    }

    @Test func itDoesntTakeClicks() {
        let (notice, parent) = placed()
        notice.show("Connected to pc")
        parent.layoutSubtreeIfNeeded()
        let middle = CGPoint(x: notice.frame.midX, y: notice.frame.midY)
        #expect(notice.hitTest(middle) == nil)
    }

    @Test func itSitsAtTheBottomInsideTheWindow() {
        let (notice, parent) = placed()
        let long = "Couldn't read the settings, so the defaults are used. The old file is app.toml.bad."
        notice.show(long)
        parent.layoutSubtreeIfNeeded()
        #expect(notice.frame.minY >= 0 && notice.frame.minY < 20)
        #expect(notice.frame.minX >= 0 && notice.frame.maxX <= 300)
    }
}
```

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneUnitTests/NoticeQueueTests -only-testing:LiveSplitOneUnitTests/LaunchNoticesTests -only-testing:LiveSplitOneHeadlessUITests/NoticeViewTests`
Expected: build fails: `NoticeQueue`, `LaunchNotices` and `NoticeView` aren't found.

- [ ] **Step 2: Write `NoticeQueue`**

`App/TimerWindow/NoticeQueue.swift`:

```swift
import Foundation

/// The overlay notices (spec §6): each shows for 4 seconds, one at a time, in the order they
/// came. A notice already shown or waiting isn't queued again, so a repeated status doesn't pile
/// up.
@MainActor
final class NoticeQueue {
    /// Runs an action on the main actor after a delay in seconds.
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    static let duration: TimeInterval = 4

    /// Called with the notice to show, or `nil` when none is left.
    var onChange: ((String?) -> Void)?
    private(set) var current: String?
    private(set) var waiting: [String] = []
    private let schedule: Schedule

    init(schedule: @escaping Schedule = NoticeQueue.afterDelay) {
        self.schedule = schedule
    }

    func show(_ text: String) {
        guard text != current, !waiting.contains(text) else { return }
        if current == nil {
            present(text)
        } else {
            waiting.append(text)
        }
    }

    private func present(_ text: String) {
        current = text
        onChange?(text)
        schedule(Self.duration) { [weak self] in self?.next() }
    }

    private func next() {
        if waiting.isEmpty {
            current = nil
            onChange?(nil)
        } else {
            present(waiting.removeFirst())
        }
    }

    static func afterDelay(_ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void)
    {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
}
```

- [ ] **Step 3: Write `NoticeView`**

`App/TimerWindow/NoticeView.swift`:

```swift
import AppKit

/// One overlay notice, drawn over the bottom of the timer (spec §6). Not part of the layout:
/// it is a view above the layout's image, never drawn into it.
@MainActor
final class NoticeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private static let margin: CGFloat = 6
    private static let padding = CGSize(width: 8, height: 4)

    var text: String { label.stringValue }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer?.cornerRadius = 6
        isHidden = true

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.setAccessibilityIdentifier("overlay-notice")
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding.width),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding.width),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding.height),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoticeView is built in code")
    }

    /// Adds the notice to `view`, centred at its bottom and never wider than it.
    func place(in view: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.margin),
            widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -2 * Self.margin),
        ])
    }

    /// Shows `text`, or hides the notice when it is `nil`. VoiceOver reads each new notice.
    func show(_ text: String?) {
        label.stringValue = text ?? ""
        isHidden = text == nil
        guard let text else { return }
        NSAccessibility.post(
            element: label, notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    override func layout() {
        // A wrapping label needs a width to wrap at.
        let available = (superview?.bounds.width ?? 0) - 2 * (Self.margin + Self.padding.width)
        label.preferredMaxLayoutWidth = max(available, 0)
        super.layout()
    }

    /// Clicks go through to the timer, so a drag that starts here still moves the window.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
```

- [ ] **Step 4: Write `LaunchNotices`**

`App/TimerWindow/LaunchNotices.swift`:

```swift
/// The overlay notices shown at launch (spec §6, §10).
enum LaunchNotices {
    /// The notice for what reading `app.toml` found, if it needs one.
    static func settings(_ outcome: SettingsStore.LoadOutcome) -> String? {
        switch outcome {
        case .missing, .loaded:
            nil
        case .recovered:
            "Couldn't read the settings, so the defaults are used. The old file is app.toml.bad."
        case .unrecoverable:
            "Couldn't read the settings, so the defaults are used and changes aren't saved."
        }
    }
}
```

- [ ] **Step 5: Run the tests**

Run the command from Step 1.
Expected: all pass. If `itSitsAtTheBottomInsideTheWindow` fails because the frame is still zero, call `parent.layoutSubtreeIfNeeded()` twice (the label's wrap width is set during the first pass) and say so in the pull request.

- [ ] **Step 6: Commit**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
git add App/TimerWindow Tests/Unit Tests/HeadlessUI
git commit -m "feat: show overlay notices one after another"
```

---

### Task 6: `TimerContent` and `TimerView`: drawing on each display refresh

**Files:**
- Create: `App/TimerWindow/TimerContent.swift`
- Create: `App/TimerWindow/TimerView.swift`
- Create: `Tests/HeadlessUI/TimerViewTests.swift`

**Interfaces:**
- Consumes: `LayoutRenderer`, `RenderedFrame` (Task 2); `WindowPlacement.size(forHint:scale:)` (Task 4); generated `Layout`, `LayoutState`, `ImageCache`, `Run`, `Segment`, `Timer`, `SharedTimer`, `Lang`.
- Produces:
  - `@MainActor final class TimerContent { let timer: SharedTimer; let layout: Layout; let imageCache: ImageCache; init(lang: UInt8 = TimerContent.systemLanguage); static var systemLanguage: UInt8 { get }; static func defaultRun() -> Run; func render(pixelWidth: Int, pixelHeight: Int) -> RenderedFrame }`.
  - `@MainActor final class TimerView: NSView { let content: TimerContent; var onSizeHint: ((CGSize) -> Void)?; private(set) var framesDrawn: Int; func drawFrame() }`. Task 7 sets `onSizeHint`.

Key facts:
- `NSView.displayLink(target:selector:)` (macOS 14 and later) gives a `CADisplayLink` that follows the view's screen and its refresh rate, and stops while the view isn't on screen. It must be added to a run loop, and invalidated when the view leaves its window, since it retains its target.
- The timer's read lock is held only while updating the layout state: `TimerContent.render` disposes the lock before drawing (spec §5.1).
- A layer-backed view with `layerContentsRedrawPolicy = .never` and its image in `layer.contents` never calls `draw(_:)`. With `contentsGravity = .resize`, the image fills the view while a resize is in progress, until the next frame draws at the new size.
- `mouseDownCanMoveWindow = true` with the window's `isMovableByWindowBackground = true` (Task 7) lets a drag anywhere move the window.
- The headless tests have no window, so `convertToBacking` uses a scale of 1 there. They test drawing, not the scale; the snapshot at 2× (Task 2) and Task 9's hand check cover Retina.

- [ ] **Step 1: Write the failing tests**

`Tests/HeadlessUI/TimerViewTests.swift`:

```swift
import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerViewTests {
    private func makeView(width: CGFloat = 300, height: CGFloat = 500) -> TimerView {
        let view = TimerView(content: TimerContent(lang: 0))
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return view
    }

    @Test func theFirstFrameShowsTheLayout() {
        let view = makeView()
        view.drawFrame()
        #expect(view.framesDrawn == 1)
        #expect(view.layer?.contents != nil)
    }

    @Test func anIdleTimerIsntDrawnAgain() {
        let view = makeView()
        view.drawFrame()
        view.drawFrame()
        view.drawFrame()
        #expect(view.framesDrawn == 1)
    }

    @Test func aResizedViewIsDrawnAgain() {
        let view = makeView()
        view.drawFrame()
        view.setFrameSize(CGSize(width: 320, height: 500))
        view.drawFrame()
        #expect(view.framesDrawn == 2)
    }

    @Test func anEmptyViewDrawsNothing() {
        let view = makeView(width: 0, height: 0)
        view.drawFrame()
        #expect(view.framesDrawn == 0)
    }

    @Test func dragsMoveTheWindow() {
        #expect(makeView().mouseDownCanMoveWindow)
    }

    @Test func theLayoutIsNamedForAccessibility() {
        let view = makeView()
        #expect(view.accessibilityIdentifier() == "timer-layout")
        #expect(view.accessibilityRole() == .image)
    }

    @Test func theDefaultRunIsLiveSplitOnes() {
        let run = TimerContent.defaultRun()
        #expect(run.len() == 1)
        #expect(run.segment(0).name() == "Time")
    }
}
```

Check the generated names before running: `grep -n 'func len()\|func segment(_\|func name()' LiveSplitCore/Generated/LiveSplitCore.swift | head`. If `Run`'s are named differently, use the generated names in the test and say so in the pull request.

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneHeadlessUITests/TimerViewTests`
Expected: build fails: `TimerView` and `TimerContent` aren't found.

- [ ] **Step 2: Write `TimerContent`**

`App/TimerWindow/TimerContent.swift`:

```swift
import Foundation
import LiveSplitCore

/// The timer, the layout and what the window draws from them (spec §5). Until #12 opens files,
/// it holds livesplit-core's default layout and LiveSplit One's new run.
@MainActor
final class TimerContent {
    /// The one timer (spec §5.1). Commands reach it through an `EventSink` built on it.
    let timer: SharedTimer
    let layout: Layout
    let imageCache = ImageCache()
    private let state: LayoutState
    private let renderer = LayoutRenderer()
    private let lang: UInt8

    init(lang: UInt8 = TimerContent.systemLanguage) {
        self.lang = lang
        layout = Layout.defaultLayout(lang)
        // A run with one segment always makes a timer.
        timer = LiveSplitCore.Timer(Self.defaultRun())!.intoShared()
        let lock = timer.read()
        state = layout.state(imageCache, lock.timer(), lang)
        lock.dispose()
    }

    /// The layout's language: macOS's first preferred language, as LiveSplit One uses the
    /// browser's.
    static var systemLanguage: UInt8 {
        Lang.parseLocale(Locale.preferredLanguages.first ?? "en")
    }

    /// LiveSplit One's new run: one segment named "Time".
    static func defaultRun() -> Run {
        let run = Run()
        run.pushSegment(Segment("Time"))
        return run
    }

    /// Updates the layout's state from the timer, then renders it at the size in pixels if
    /// anything changed. Holds the timer's read lock only while updating (spec §5.1).
    func render(pixelWidth: Int, pixelHeight: Int) -> RenderedFrame {
        let lock = timer.read()
        layout.updateState(state, imageCache, lock.timer(), lang)
        lock.dispose()
        return renderer.render(state, imageCache, width: pixelWidth, height: pixelHeight)
    }
}
```

- [ ] **Step 3: Write `TimerView`**

`App/TimerWindow/TimerView.swift`:

```swift
import AppKit
import LiveSplitCore

/// Shows the rendered layout. On each display refresh it renders a frame, which draws only when
/// the layout or the size changed (spec §5.2).
@MainActor
final class TimerView: NSView {
    let content: TimerContent
    /// Called with the layout's natural size in points after its height changes.
    var onSizeHint: ((CGSize) -> Void)?
    /// How many frames were drawn, for tests.
    private(set) var framesDrawn = 0
    private var displayLink: CADisplayLink?

    init(content: TimerContent) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Timer")
        setAccessibilityIdentifier("timer-layout")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimerView is built in code")
    }

    /// A drag anywhere moves the window, which has no title bar (spec §6).
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(refresh(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
    }

    @objc private func refresh(_ link: CADisplayLink) {
        drawFrame()
    }

    /// Renders one frame at the view's size in pixels. Each display refresh calls it.
    func drawFrame() {
        let pixels = convertToBacking(bounds).size
        let frame = content.render(
            pixelWidth: Int(pixels.width.rounded()), pixelHeight: Int(pixels.height.rounded()))
        if let image = frame.image {
            layer?.contents = image
            framesDrawn += 1
        }
        if let hint = frame.sizeHint,
            let size = WindowPlacement.size(
                forHint: hint, scale: window?.backingScaleFactor ?? 1)
        {
            onSizeHint?(size)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run the command from Step 1.
Expected: 7 tests pass. If the hosted test bundle can't see `LiveSplitCore`'s types, as in `cannot find type 'Run' in scope`, add `import LiveSplitCore` to the test file. If the module isn't found then, stop and report: the headless target would need `LiveSplitCore` in its dependencies in `project.yml`.

- [ ] **Step 5: Commit**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
git add App/TimerWindow Tests/HeadlessUI/TimerViewTests.swift
git commit -m "feat: draw the layout on each display refresh"
```

---

### Task 7: The borderless window, its frame, Always on Top, and the launch

**Files:**
- Create: `App/TimerWindow/TimerWindow.swift`
- Create: `App/TimerWindow/TimerWindowController.swift`
- Modify: `App/AppDelegate.swift`
- Modify: `project.yml` (the headless tests use `TemporaryFolder`)
- Modify: `Tests/HeadlessUI/TimerWindowTests.swift` (rewritten)
- Modify: `LiveSplitCore/CLiveSplitCore/include/module.modulemap` (only if Step 6 finds missing symbols)
- Modify: `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md` (§5.2, §6)

**Interfaces:**
- Consumes: `TimerContent`, `TimerView` (Task 6); `NoticeQueue`, `NoticeView`, `LaunchNotices` (Task 5); `WindowPlacement` (Task 4); `Settings.frame(forLayout:)`, `setFrame(_:forLayout:)` (Task 3); `SettingsStore`.
- Produces:
  - `final class TimerWindow: NSWindow { init(contentRect: CGRect); func setAlwaysOnTop(_ on: Bool) }`.
  - `@MainActor final class TimerWindowController: NSObject, NSWindowDelegate { static let saveDelay: Duration; let window: TimerWindow; let timerView: TimerView; let notices: NoticeQueue; let content: TimerContent; private(set) var layoutPath: String?; init(content:settings:screens:mainScreen:notices:); static func make(content:settings:) -> TimerWindowController; var shownNotice: String? { get }; func toggleAlwaysOnTop(); func fitLayout(_ size: CGSize); func saveFrame(); func saveFrameIfPending() }`.
  - `AppDelegate.timerWindow: TimerWindowController?`, `AppDelegate.window: NSWindow?` (now computed), `@objc AppDelegate.toggleAlwaysOnTop(_:)`.

Key facts:
- A borderless window can't become key or main unless it says so. The timer needs key focus for #13's keyboard shortcuts and menus, so `TimerWindow` overrides both.
- `.borderless` with `.resizable` lets a window resize from its edges. Task 8's E2E test checks that on a real window, and has the fallback if it doesn't.
- `windowDidMove` comes during a drag, and `windowDidResize` on every step of a live resize. Saving waits until `saveDelay` after the last one, so a drag writes once (Review Focus 4). `windowDidEndLiveResize` saves at once. `setFrame` inside `fitLayout` posts `windowDidResize` before `fitLayout` saves, which cancels that pending save.
- The initial frame is set before the window gets its delegate, so placing the window at launch saves nothing. A launch without a move never writes `app.toml` (the E2E test from #49 checks that).
- With `isOpaque = false` and a clear background, a layout with a transparent background shows what is behind the window, as LiveSplit One shows the page behind its canvas.

- [ ] **Step 1: Let the headless tests use `TemporaryFolder`**

In `project.yml`, change `LiveSplitOneHeadlessUITests`'s `sources: [Tests/HeadlessUI]` to:

```yaml
    sources:
      - Tests/HeadlessUI
      # Shared with the unit tests.
      - Tests/Unit/Support/TemporaryFolder.swift
```

- [ ] **Step 2: Write the failing tests**

Replace `Tests/HeadlessUI/TimerWindowTests.swift` with:

```swift
import AppKit
import Testing

@testable import LiveSplitOne

@MainActor
@Suite struct TimerWindowTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func makeController(
        _ store: SettingsStore, notices: NoticeQueue = NoticeQueue(schedule: { _, _ in })
    ) -> TimerWindowController {
        TimerWindowController(
            content: TimerContent(lang: 0), settings: store, screens: [screen],
            mainScreen: screen, notices: notices)
    }

    @Test func theWindowIsBorderlessResizableAndNamed() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.resizable))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.isMovableByWindowBackground)
        #expect(window.canBecomeKey && window.canBecomeMain)
        #expect(window.accessibilityIdentifier() == "timer-window")
        #expect(window.title == "LiveSplit One")
        #expect(window.contentView?.accessibilityIdentifier() == "timer-layout")
    }

    @Test func theWindowIsNotShownUntilAsked() throws {
        let folder = try TemporaryFolder()
        #expect(!makeController(SettingsStore(directory: folder.url)).window.isVisible)
    }

    @Test func withNoSavedFrameItIsCentredAtLiveSplitOnesSize() throws {
        let folder = try TemporaryFolder()
        let window = makeController(SettingsStore(directory: folder.url)).window
        #expect(window.frame == CGRect(x: 570, y: 187.5, width: 300, height: 500))
    }

    @Test func aSavedFrameOnScreenIsUsed() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update {
            $0.setFrame(WindowFrame(x: 100, y: 200, width: 250, height: 400), forLayout: nil)
        }
        #expect(makeController(store).window.frame == CGRect(x: 100, y: 200, width: 250, height: 400))
    }

    @Test func aSavedFrameOffScreenIsIgnored() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update {
            $0.setFrame(WindowFrame(x: 5000, y: 200, width: 250, height: 400), forLayout: nil)
        }
        #expect(makeController(store).window.frame.size == CGSize(width: 300, height: 500))
    }

    @Test func savingTheFrameStoresItForTheDefaultLayout() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        controller.window.setFrame(CGRect(x: 50, y: 60, width: 320, height: 480), display: false)

        controller.saveFrame()

        #expect(
            store.settings.frame(forLayout: nil)
                == WindowFrame(x: 50, y: 60, width: 320, height: 480))
        #expect(try folder.read("app.toml").contains("[default_layout_window]"))
    }

    @Test func openingTheWindowSavesNothing() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        controller.saveFrameIfPending()
        #expect(try folder.names().isEmpty)
    }

    @Test func aSizeHintResizesTheWindowKeepingItsTopLeft() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        let before = controller.window.frame

        controller.fitLayout(CGSize(width: 300, height: 600))

        let after = controller.window.frame
        #expect(after.size == CGSize(width: 300, height: 600))
        #expect(after.minX == before.minX && after.maxY == before.maxY)
        #expect(store.settings.frame(forLayout: nil) == WindowPlacement.windowFrame(after))
    }

    @Test func alwaysOnTopComesFromTheSettings() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        store.update { $0.alwaysOnTop = true }
        #expect(makeController(store).window.level == .floating)
    }

    @Test func togglingAlwaysOnTopChangesTheWindowAndSavesIt() throws {
        let folder = try TemporaryFolder()
        let store = SettingsStore(directory: folder.url)
        let controller = makeController(store)
        #expect(controller.window.level == .normal)

        controller.toggleAlwaysOnTop()

        #expect(controller.window.level == .floating)
        #expect(store.settings.alwaysOnTop)
        #expect(try folder.read("app.toml").contains("always_on_top = true"))
    }

    @Test func noticesShowOverTheTimer() throws {
        let folder = try TemporaryFolder()
        let controller = makeController(SettingsStore(directory: folder.url))
        #expect(controller.shownNotice == nil)
        controller.notices.show("Connected to pc")
        #expect(controller.shownNotice == "Connected to pc")
    }
}
```

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneHeadlessUITests/TimerWindowTests`
Expected: build fails: `TimerWindowController` isn't found.

- [ ] **Step 3: Write `TimerWindow`**

`App/TimerWindow/TimerWindow.swift`:

```swift
import AppKit

/// The timer window (spec §6): borderless, moved by dragging anywhere in it, resized from its
/// edges.
final class TimerWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered,
            defer: false)
        // For the Window menu, Mission Control and accessibility; it has no title bar to show it.
        title = "LiveSplit One"
        setAccessibilityIdentifier("timer-window")
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        // A layout with a transparent background shows what is behind the window.
        isOpaque = false
        backgroundColor = .clear
        minSize = WindowPlacement.minimumSize
    }

    // A borderless window can't become key unless it says so. The timer needs key focus for its
    // keyboard shortcuts and menus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Always on Top (spec §6): above other apps' windows.
    func setAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }
}
```

- [ ] **Step 4: Write `TimerWindowController`**

`App/TimerWindow/TimerWindowController.swift`:

```swift
import AppKit

/// The timer window with its contents and notices: where it goes, what it remembers, and how it
/// follows the layout's size (spec §5.2, §6).
@MainActor
final class TimerWindowController: NSObject, NSWindowDelegate {
    /// How long after the window stops moving its frame is saved, so a drag saves once.
    static let saveDelay: Duration = .milliseconds(500)

    let window: TimerWindow
    let timerView: TimerView
    let notices: NoticeQueue
    let content: TimerContent
    /// The open layout's path, or `nil` for the default layout. #12 sets it.
    private(set) var layoutPath: String?
    private let noticeView = NoticeView()
    private let settings: SettingsStore
    private var pendingSave: Task<Void, Never>?

    /// `screens` are the screens' visible frames; `mainScreen` is where a window with no usable
    /// saved frame goes.
    init(
        content: TimerContent, settings: SettingsStore, screens: [CGRect], mainScreen: CGRect,
        notices: NoticeQueue = NoticeQueue()
    ) {
        self.content = content
        self.settings = settings
        self.notices = notices
        let frame =
            WindowPlacement.restoredFrame(settings.settings.frame(forLayout: nil), screens: screens)
            ?? WindowPlacement.centred(WindowPlacement.defaultSize, on: mainScreen)
        window = TimerWindow(contentRect: frame)
        timerView = TimerView(content: content)
        super.init()

        window.contentView = timerView
        noticeView.place(in: timerView)
        window.setAlwaysOnTop(settings.settings.alwaysOnTop)
        notices.onChange = { [weak self] text in self?.noticeView.show(text) }
        timerView.onSizeHint = { [weak self] size in self?.fitLayout(size) }
        // Last, so placing the window above saves nothing.
        window.delegate = self
    }

    /// A controller for the screens AppKit reports.
    static func make(content: TimerContent, settings: SettingsStore) -> TimerWindowController {
        let main =
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return TimerWindowController(
            content: content, settings: settings, screens: NSScreen.screens.map(\.visibleFrame),
            mainScreen: main)
    }

    /// The notice on screen, if any.
    var shownNotice: String? { noticeView.isHidden ? nil : noticeView.text }

    /// Always on Top (spec §6), saved in `app.toml`.
    func toggleAlwaysOnTop() {
        settings.update { $0.alwaysOnTop.toggle() }
        window.setAlwaysOnTop(settings.settings.alwaysOnTop)
    }

    /// Gives the window the layout's natural size, keeping its top-left corner, as LiveSplit One
    /// does when the renderer gives a size hint (spec §5.2).
    func fitLayout(_ size: CGSize) {
        window.setFrame(WindowPlacement.resized(window.frame, to: size), display: true)
        saveFrame()
    }

    /// Saves the window's frame for the open layout now.
    func saveFrame() {
        pendingSave?.cancel()
        pendingSave = nil
        let frame = WindowPlacement.windowFrame(window.frame)
        settings.update { $0.setFrame(frame, forLayout: layoutPath) }
    }

    /// Saves the frame if a move or resize hasn't been saved yet, as when the app quits.
    func saveFrameIfPending() {
        if pendingSave != nil { saveFrame() }
    }

    func windowDidMove(_ notification: Notification) {
        scheduleSave()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    /// Saves the frame `saveDelay` after the last move or resize step.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveFrame()
        }
    }
}
```

- [ ] **Step 5: Use it at launch**

In `App/AppDelegate.swift`:

1. Replace `private(set) var window: NSWindow?` with:

```swift
    /// The timer window (spec §6).
    private(set) var timerWindow: TimerWindowController?
    var window: NSWindow? { timerWindow?.window }
```

2. In `applicationDidFinishLaunching`, replace everything after the `Log.shared.record(…)` statement with:

```swift
        let settings = SettingsStore(directory: ConfigFolder.current)
        self.settings = settings
        let timerWindow = TimerWindowController.make(content: TimerContent(), settings: settings)
        timerWindow.window.makeKeyAndOrderFront(nil)
        if let notice = LaunchNotices.settings(settings.loadOutcome) {
            timerWindow.notices.show(notice)
        }
        self.timerWindow = timerWindow
```

3. After `applicationShouldTerminateAfterLastWindowClosed`, add:

```swift
    func applicationWillTerminate(_ notification: Notification) {
        timerWindow?.saveFrameIfPending()
    }

    /// Always on Top (spec §6). The menu items that send it come with #13.
    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        timerWindow?.toggleAlwaysOnTop()
    }
```

4. Delete `static func makeWindow()` and the comment "Later issues replace the window's contents with the timer (spec §6)." in the class comment. The class comment becomes: "Starts the app and opens the timer window. No storyboards: everything is built in code (spec §4)."

- [ ] **Step 6: Run the tests, and check the app links in Debug and Release**

```bash
xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' \
  -only-testing:LiveSplitOneHeadlessUITests -only-testing:LiveSplitOneUnitTests
scripts/build-app.sh 0.0.0-dev
```

Expected: the tests pass, and `scripts/build-app.sh` makes the universal release build. This is the first time `App/` calls into `LiveSplitCore` (#11's comment on the link). If either link fails with `Undefined symbols`, add what's missing to `LiveSplitCore/CLiveSplitCore/include/module.modulemap`, after `link framework "CoreGraphics"`. The comment lists what a plain C link needed:

```
    link framework "ApplicationServices"
    link framework "CoreText"
    link framework "Security"
    link framework "SystemConfiguration"
    link "iconv"
```

Add only the ones the linker asks for, run both again, and say in the pull request which were needed.

- [ ] **Step 7: Look at it**

```bash
xcodebuild build -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -derivedDataPath build/dd
open "build/dd/Build/Products/Debug/LiveSplit One.app" --args -LSOConfigDirectory /private/tmp/lso-look/Config -LSOLogDirectory /private/tmp/lso-look/Logs
```

Expected: a 300 × 500 window with no title bar, in the middle of the screen, showing the default layout with one segment, **Time**. Drag it by its middle: it moves. Drag an edge: it resizes, and the layout stretches to fill it. Open Activity Monitor: with the timer idle, the app's CPU stays near 0 %. Quit with ⌘Q.

- [ ] **Step 8: Update the spec**

In §5.2:

- Replace the bullet "The renderer only draws again when the layout state changed or the size changed, so an idle timer uses next to no CPU." with: "The renderer only draws again when the layout state changed or the size changed, so an idle timer uses next to no CPU. `core/` compares each frame's layout state, encoded as JSON, with the last frame's (section 5.3)."
- Replace the bullet "The renderer's size hint after a layout loads gives the window its natural aspect ratio, as in LiveSplit One." with: "A new layout starts at 300 × 500 points, LiveSplit One's default. When the layout's height changes (another layout opens, segments are added), the renderer gives a size hint, and the window takes that size, keeping its top-left corner, as LiveSplit One does."
- Add: "The layout's text, such as component names, is in macOS's first preferred language when livesplit-core has it, as LiveSplit One follows the browser's language."

In §6:

- Replace the **Size and position** bullet with: "**Size and position** are remembered per layout file in `app.toml`, and for the default layout, which has no file, in a key of its own (section 11). A layout opened for the first time keeps the window's size until the renderer's size hint changes it (section 5.2). A saved frame with less than 40 × 40 points on any screen is ignored, and the window is centred on the main screen instead, since it has no title bar to drag it back with."
- In the **On launch** bullet, after "uses livesplit-core's default layout or an empty run", add "(LiveSplit One's new run: one segment named Time)".
- In the **Overlay notices** bullet, add at the end: "When several come together, each shows for its 4 seconds in turn. One already shown or waiting isn't repeated."

- [ ] **Step 9: Commit**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
git add App project.yml Tests/HeadlessUI LiveSplitCore/CLiveSplitCore/include/module.modulemap docs/superpowers/specs/
git commit -m "feat: show the timer in a borderless window"
```

---

### Task 8: E2E: the first launch, moving, relaunching and resizing

**Files:**
- Modify: `Tests/E2E/E2EApp.swift`
- Create: `Tests/E2E/TimerWindowTests.swift`
- Modify: `Tests/E2E/LaunchTests.swift` (deleted if Step 1 makes it a duplicate)
- Create: `App/TimerWindow/ResizeEdges.swift`, `Tests/Unit/ResizeEdgesTests.swift`, and modify `App/TimerWindow/TimerView.swift`: **only if Step 4 fails** (Step 5)

**Interfaces:**
- Consumes: the app as built by Tasks 1–7; `E2EApp`.
- Produces: `E2EApp.relaunch()`, `E2EApp.settingsText(containing:timeout:) -> String?`. #12 and #18 use them.

Key facts:
- `XCUIApplication.terminate()` kills the app without `applicationWillTerminate`, so the test waits for `app.toml` to hold the new frame before relaunching. The frame is saved half a second after the drag ends.
- `XCUIElement.frame` is in screen points with the origin at the top left. The test compares frames from XCUITest only, so the coordinate system doesn't matter.
- `XCUICoordinate.press(forDuration:thenDragTo:)` drags with the mouse, as a user does.
- The runner can read files the app writes (the E2E notes on #18), so `settingsText` reads `app.toml` from the test's config folder.

- [ ] **Step 1: Add to the harness**

In `Tests/E2E/E2EApp.swift`, add inside the class:

```swift
    /// Quits the app and launches it again with the same folders, as a user relaunching it.
    /// `terminate()` doesn't let the app save on quit, so wait for what it must save first.
    func relaunch() {
        app.terminate()
        app.launch()
    }

    /// The text of `app.toml` once it contains `text`, or `nil` if it doesn't within `timeout`
    /// seconds.
    func settingsText(containing text: String, timeout: TimeInterval = 10) -> String? {
        let file = configFolder.appending(path: "app.toml")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let all = try? String(contentsOf: file, encoding: .utf8), all.contains(text) {
                return all
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }
```

- [ ] **Step 2: Write the tests**

`Tests/E2E/TimerWindowTests.swift`:

```swift
import AppKit
import XCTest

/// The timer window as a user sees and handles it (spec §6, §14.3).
final class TimerWindowTests: XCTestCase {
    /// The number of different colours in a sample of the element's pixels. An empty window has
    /// one or two; a drawn layout, with its text, many more.
    @MainActor
    private func colours(in element: XCUIElement) -> Int {
        guard
            let image = element.screenshot().image.cgImage(
                forProposedRect: nil, context: nil, hints: nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return 0 }
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return 0 }
        var seen = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count, by: 4 * 7) {
            seen.insert(
                UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8
                    | UInt32(pixels[index + 2]))
        }
        return seen.count
    }

    @MainActor
    func testFirstLaunchShowsTheDefaultLayout() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        XCTAssertEqual(window.frame.size, CGSize(width: 300, height: 500))
        let layout = window.images["timer-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while colours(in: window) <= 10, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(colours(in: window), 10, "the window shows no layout")
    }

    @MainActor
    func testTheWindowMovesAndOpensThereAgain() throws {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.2, thenDragTo: middle.withOffset(CGVector(dx: 120, dy: 80)))

        let moved = window.frame
        XCTAssertEqual(moved.minX, before.minX + 120, accuracy: 2)
        XCTAssertEqual(moved.minY, before.minY + 80, accuracy: 2)
        XCTAssertNotNil(e2e.settingsText(containing: "[default_layout_window]"))

        e2e.relaunch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.frame.minX, moved.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, moved.minY, accuracy: 1)
        XCTAssertEqual(window.frame.size, moved.size)
    }

    @MainActor
    func testTheWindowResizesFromItsCorner() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 60, dy: 40)))

        XCTAssertEqual(window.frame.width, before.width + 60, accuracy: 3)
        XCTAssertEqual(window.frame.height, before.height + 40, accuracy: 3)
        XCTAssertEqual(window.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, before.minY, accuracy: 1)
    }
}
```

`LaunchTests.testLaunchShowsTheTimerWindow` only checks that the window exists, which `testFirstLaunchShowsTheDefaultLayout` now checks too. Delete `Tests/E2E/LaunchTests.swift`.

- [ ] **Step 3: Run the E2E tests**

Run: `xcodegen generate && xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS' -only-testing:LiveSplitOneE2ETests`
Expected: all E2E tests pass, including `SettingsTests.testTheFirstLaunchWritesNoSettings` and the logging tests. The first run may ask for permission for Xcode's test runner to control the computer; allow it.

- [ ] **Step 4: If the corner drag didn't resize**

If `testTheWindowResizesFromItsCorner` fails because the size didn't change, borderless windows don't resize from their edges on this macOS, and Step 5 adds the resizing. If it passed, skip Step 5 and go to Step 6.

- [ ] **Step 5 (only if Step 4 failed): Resize from the edges by hand**

`App/TimerWindow/ResizeEdges.swift`:

```swift
import CoreGraphics

/// The edges a press near the window's border grabs, and the frame a drag gives. Needed because
/// borderless windows don't resize from their edges on their own.
struct ResizeEdges: OptionSet {
    let rawValue: Int

    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let bottom = ResizeEdges(rawValue: 1 << 2)
    static let top = ResizeEdges(rawValue: 1 << 3)
    /// How close to an edge, in points, a press grabs it.
    static let margin: CGFloat = 5

    /// The edges within `margin` of `point`, in a view's `bounds` (origin at the bottom left).
    static func at(_ point: CGPoint, in bounds: CGRect) -> ResizeEdges {
        var edges: ResizeEdges = []
        if point.x <= bounds.minX + margin { edges.insert(.left) }
        if point.x >= bounds.maxX - margin { edges.insert(.right) }
        if point.y <= bounds.minY + margin { edges.insert(.bottom) }
        if point.y >= bounds.maxY - margin { edges.insert(.top) }
        return edges
    }

    /// `frame` with these edges moved by `delta` (screen points, y up), at least `minSize`. The
    /// opposite edges stay where they are.
    func resize(_ frame: CGRect, by delta: CGSize, minSize: CGSize) -> CGRect {
        var result = frame
        if contains(.right) { result.size.width = max(minSize.width, frame.width + delta.width) }
        if contains(.left) {
            result.size.width = max(minSize.width, frame.width - delta.width)
            result.origin.x = frame.maxX - result.width
        }
        if contains(.top) { result.size.height = max(minSize.height, frame.height + delta.height) }
        if contains(.bottom) {
            result.size.height = max(minSize.height, frame.height - delta.height)
            result.origin.y = frame.maxY - result.height
        }
        return result
    }
}
```

`Tests/Unit/ResizeEdgesTests.swift`:

```swift
import CoreGraphics
import Testing

@testable import LiveSplitOne

@Suite struct ResizeEdgesTests {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
    let frame = CGRect(x: 100, y: 100, width: 300, height: 500)
    let minimum = CGSize(width: 40, height: 20)

    @Test func pressesNearTheBorderGrabItsEdges() {
        #expect(ResizeEdges.at(CGPoint(x: 2, y: 250), in: bounds) == .left)
        #expect(ResizeEdges.at(CGPoint(x: 298, y: 2), in: bounds) == [.right, .bottom])
        #expect(ResizeEdges.at(CGPoint(x: 150, y: 498), in: bounds) == .top)
        #expect(ResizeEdges.at(CGPoint(x: 150, y: 250), in: bounds).isEmpty)
    }

    @Test func draggingTheBottomRightCornerKeepsTheTopLeft() {
        let resized = ResizeEdges([.right, .bottom])
            .resize(frame, by: CGSize(width: 60, height: -40), minSize: minimum)
        #expect(resized == CGRect(x: 100, y: 60, width: 360, height: 540))
    }

    @Test func draggingTheLeftEdgeKeepsTheRight() {
        let resized = ResizeEdges.left
            .resize(frame, by: CGSize(width: 50, height: 0), minSize: minimum)
        #expect(resized == CGRect(x: 150, y: 100, width: 250, height: 500))
    }

    @Test func theWindowStopsAtTheMinimumSize() {
        let resized = ResizeEdges([.left, .top])
            .resize(frame, by: CGSize(width: 1000, height: -1000), minSize: minimum)
        #expect(resized.size == minimum)
        #expect(resized.maxX == frame.maxX && resized.minY == frame.minY)
    }
}
```

In `App/TimerWindow/TimerView.swift`, replace the `mouseDownCanMoveWindow` override with the following, and change the headless test `dragsMoveTheWindow` to `#expect(!makeView().mouseDownCanMoveWindow)`, since the view now moves the window itself:

```swift
    /// The view moves and resizes the window itself (`mouseDown(with:)`), so AppKit doesn't
    /// start a move on its own.
    override var mouseDownCanMoveWindow: Bool { false }

    /// A press near an edge resizes the window; anywhere else, it moves it (spec §6).
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edges = ResizeEdges.at(convert(event.locationInWindow, from: nil), in: bounds)
        guard !edges.isEmpty else {
            window.performDrag(with: event)
            return
        }
        let start = NSEvent.mouseLocation
        let startFrame = window.frame
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking
        ) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let now = NSEvent.mouseLocation
            let delta = CGSize(width: now.x - start.x, height: now.y - start.y)
            window.setFrame(
                edges.resize(startFrame, by: delta, minSize: window.minSize), display: true)
        }
    }

    override func resetCursorRects() {
        let margin = ResizeEdges.margin
        addCursorRect(
            CGRect(x: 0, y: 0, width: margin, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(
            CGRect(x: bounds.maxX - margin, y: 0, width: margin, height: bounds.height),
            cursor: .resizeLeftRight)
        addCursorRect(
            CGRect(x: 0, y: 0, width: bounds.width, height: margin), cursor: .resizeUpDown)
        addCursorRect(
            CGRect(x: 0, y: bounds.maxY - margin, width: bounds.width, height: margin),
            cursor: .resizeUpDown)
    }
```

A live resize done this way doesn't send `windowDidEndLiveResize`, but each step sends `windowDidResize`, so the frame is still saved `saveDelay` after the drag ends. Run the unit, headless and E2E tests again; all pass. Say in the pull request that borderless windows didn't resize on their own, and add a sentence to spec §6's **Borderless** bullet: "The app resizes the window from its edges itself, since a borderless window doesn't."

- [ ] **Step 6: Commit**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
git add Tests/E2E App Tests/Unit Tests/HeadlessUI docs/superpowers/specs/
git commit -m "test(e2e): cover the timer window's first launch, moving and resizing"
```

---

### Task 9: The wiki, every check, and the pull request

**Files:**
- Create: `docs/wiki/The-Timer-Window.md`
- Modify: `docs/wiki/_Sidebar.md`, `docs/wiki/Home.md`, `docs/wiki/Troubleshooting.md`, `docs/wiki/Settings-and-Logs.md`

**Interfaces:**
- Consumes: the pages #25 wrote. Rebase on `main` first: `git fetch origin && git rebase origin/main`.

Key facts:
- Pages describe only what `main` does (#25's plan). There is no right-click menu yet, and no way to turn Always on Top on, so the page doesn't mention either; #13 adds them.
- The page is "The Timer Window" in spec §16.2's table, written by #11 and #13.
- Notice texts are bold and written exactly as `LaunchNotices` has them.

- [ ] **Step 1: Write the page**

`docs/wiki/The-Timer-Window.md`:

```markdown
The timer window shows your layout and nothing else. It has no title bar and no buttons.

<!-- screenshot: S1 timer-window.png --> The timer window with a layout, running.

## Moving and resizing

Drag anywhere in the window to move it. Drag an edge or a corner to resize it. The layout stretches to fill the window, as it does in LiveSplit One.

## Size and position

The first time, the window opens in the middle of the screen at 300 × 500 points, LiveSplit One's size for a new layout. After that it opens where you left it, at the size you left it.

When the layout gets taller or shorter, the window grows or shrinks with it and keeps its top-left corner where it is.

If the place the window was last isn't on a screen any more, for example after unplugging a display, it opens in the middle of the main screen instead.

## What it shows at first

Until you open your own splits and layout, the window shows LiveSplit One's default layout and a run with one segment, **Time**.

The layout's own words, such as **Previous Segment**, are in your Mac's language when LiveSplit One has it, and in English otherwise.

## Notices

Short messages sometimes appear over the bottom of the timer, for 4 seconds each. They aren't part of the layout and are never saved. When several come at once, they appear one after another.

| Notice | What it means |
|---|---|
| **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** | The settings file was damaged, so the app started with the default settings and kept the old file. See [Troubleshooting](Troubleshooting#the-settings-were-reset). |
| **Couldn't read the settings, so the defaults are used and changes aren't saved.** | The settings file couldn't be read, nor set aside. The app won't save settings until it restarts, so the file isn't overwritten. See [Troubleshooting](Troubleshooting#changes-to-the-settings-arent-saved). |
```

- [ ] **Step 2: Link it**

In `docs/wiki/_Sidebar.md`, add `- [The Timer Window](The-Timer-Window)` after the Installing line (spec §16.2's order, with Getting Started not written yet).

In `docs/wiki/Home.md`, under "## More", add as the first item: `- [The Timer Window](The-Timer-Window): moving and resizing the window, and the notices it shows.`

- [ ] **Step 3: Add to Troubleshooting and Settings and Logs**

In `docs/wiki/Troubleshooting.md`, change the start of "The settings were reset" to say what the user sees: replace its first sentence with "The timer showed **Couldn't read the settings, so the defaults are used. The old file is app.toml.bad.** The app couldn't read its settings file, so it started with the defaults." Then add, after that section:

```markdown
## Changes to the settings aren't saved

The timer showed **Couldn't read the settings, so the defaults are used and changes aren't saved.** The app couldn't read its settings file, and couldn't move it aside either, usually because of the file's or the folder's permissions. So that your file isn't lost, the app doesn't save settings until it restarts.

Quit the app, then in Finder check that you can open `app.toml` in the folder [Settings and Logs](Settings-and-Logs#settings) names. Fix its permissions, or move it somewhere else, and open the app again.

## The window is somewhere I can't see

The window opens where it was last. If that place isn't on a screen any more, it opens in the middle of the main screen. If it's on a screen you can't see, quit the app, move `app.toml` out of its folder (see [Settings and Logs](Settings-and-Logs#settings)), and open the app again: the window opens in the middle of the screen with the default settings.
```

In `docs/wiki/Settings-and-Logs.md`, in the sentence listing what `app.toml` holds, change "the window's position for each layout" to "the window's position and size for each layout". If #25 wrote it differently, make the same change to its wording.

- [ ] **Step 4: Check the pages**

Run: `scripts/wiki/check.sh docs/wiki`
Expected: exit 0, no output.

Then check every bold name against the app:

```bash
grep -rn "Couldn't read the settings" App/TimerWindow/LaunchNotices.swift
grep -rn '"Time"' App/TimerWindow/TimerContent.swift
```

Expected: both notice texts and the segment name are found, word for word. **Previous Segment** is livesplit-core's text: check it in `Tests/Integration/Snapshots/default-layout.png`.

- [ ] **Step 5: Run every check from `CONTRIBUTING.md`**

```bash
git fetch origin main
mise x -- npx commitlint --from origin/main --to HEAD --verbose
cargo fmt --check --manifest-path core/Cargo.toml
cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
cargo test --locked --manifest-path core/Cargo.toml
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
mise x -- actionlint
mise x -- shellcheck scripts/*.sh scripts/release/*.sh
mise x -- scripts/release/test-release-scripts.sh
xcodegen generate
xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
scripts/build-app.sh 0.0.0-dev
```

Expected: every command succeeds, and `xcodebuild test` prints `** TEST SUCCEEDED **`. Also run `scripts/wiki/check.sh docs/wiki` and the wiki script tests #25 added, if `CONTRIBUTING.md` lists them by then.

- [ ] **Step 6: Check by hand on a Retina and a non-Retina screen**

Open the release build from `dist/`. With a second, non-Retina display (or **System Settings → Displays** set to a scaled resolution), drag the window from one screen to the other: the text is sharp on both, without a blurry frame left after the move. Note in the pull request what was checked and on which displays. If no second display is available, say so: it is then left to the manual checks before the full release (spec §14.4).

- [ ] **Step 7: Open the pull request**

Push the branch and open the pull request with the template filled in:

- `Closes #11`.
- What changed and why, including every item under "Spec changes this pull request makes" and whether Task 8's Step 5 was needed.
- How it was tested: the commands above and their results, the snapshots looked at by eye, the CPU check from Task 7 Step 7, and Step 6.
- Screenshots to retake: none exist yet. S1 (`timer-window.png`) and S4 (`overlay-notice.png`) show this window, for #41.
- Each item from "Left to later issues", with its issue.

```bash
git push -u origin feat/timer-window
PR_BODY=$(mktemp)
# Write the filled-in template to "$PR_BODY", then:
gh pr create --title "feat: draw the layout in a borderless timer window" --body-file "$PR_BODY"
```

Then post the "Left to later issues" items as comments on #12, #13, #14 and #18.
