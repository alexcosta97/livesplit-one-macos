//! Rendering that skips frames when nothing changed, and passes on
//! livesplit-core's size hint (spec §5.2, §5.3). The C API's
//! `SoftwareRenderer_render` draws every frame and discards the hint.

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
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);

        let state = state(&mut layout, &mut cache, &timer);
        let rendered = renderer.render(&state, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        assert_eq!(
            rendered,
            Rendered {
                drew: true,
                size_hint: None
            }
        );
        assert!(pixels.iter().any(|&byte| byte != 0));
    }

    #[test]
    fn skips_a_frame_when_nothing_changed() {
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);
        let first = state(&mut layout, &mut cache, &timer);
        renderer.render(&first, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);
        let drawn = pixels.clone();

        let second = state(&mut layout, &mut cache, &timer);
        let rendered = renderer.render(&second, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        assert_eq!(
            rendered,
            Rendered {
                drew: false,
                size_hint: None
            }
        );
        assert_eq!(pixels, drawn);
    }

    #[test]
    fn draws_again_when_the_size_changes() {
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
        let mut renderer = Renderer::new();
        let state = state(&mut layout, &mut cache, &timer);
        renderer.render(
            &state,
            &cache,
            &mut image(WIDTH, HEIGHT),
            [WIDTH, HEIGHT],
            WIDTH,
        );

        let mut larger = image(2 * WIDTH, 2 * HEIGHT);
        let rendered = renderer.render(
            &state,
            &cache,
            &mut larger,
            [2 * WIDTH, 2 * HEIGHT],
            2 * WIDTH,
        );

        assert!(rendered.drew);
        assert!(larger.iter().any(|&byte| byte != 0));
    }

    #[test]
    fn draws_again_when_the_timer_moves() {
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
        let mut renderer = Renderer::new();
        let mut pixels = image(WIDTH, HEIGHT);
        let before = state(&mut layout, &mut cache, &timer);
        renderer.render(&before, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH);

        let _ = timer.write().unwrap().start();
        thread::sleep(Duration::from_millis(20));
        let after = state(&mut layout, &mut cache, &timer);

        assert!(
            renderer
                .render(&after, &cache, &mut pixels, [WIDTH, HEIGHT], WIDTH)
                .drew
        );
    }

    #[test]
    fn returns_the_size_hint_when_the_layout_gets_taller() {
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
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
        let (mut layout, mut cache, timer) = (
            Layout::default_layout(Lang::English),
            ImageCache::new(),
            timer(&["Time"]),
        );
        let mut renderer = Renderer::new();
        let state = state(&mut layout, &mut cache, &timer);
        let nothing = Rendered {
            drew: false,
            size_hint: None,
        };

        assert_eq!(renderer.render(&state, &cache, &mut [], [0, 0], 0), nothing);
        assert_eq!(
            renderer.render(&state, &cache, &mut [], [WIDTH, 0], WIDTH),
            nothing
        );
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
