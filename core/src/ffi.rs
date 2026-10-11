//! The C functions Swift calls, declared in
//! `LiveSplitCore/CLiveSplitCore/include/lso_core.h`. Names
//! follow livesplit-core's C API: `Type_method`.

use std::{
    cell::RefCell,
    ffi::{CStr, CString, c_char, c_void},
};

use livesplit_core::{SharedTimer, event::Result, layout::LayoutState, settings::ImageCache};

use crate::{
    protocol,
    render::{self, Rendered, Renderer},
    sink::{EventSink, Host, ResetDecision},
};

/// The app's callbacks. `context` is passed back to every callback, and
/// `release` is called once when the sink is dropped. The callbacks may be
/// called from any thread that runs a command. All callbacks must be non-null,
/// and must not call `LsoCommandSink_handle_command` (on any sink) on the
/// thread they run on (that would abort the app: `block_on` panics when nested
/// inside an `extern "C"` function). Dispatch asynchronously instead.
///
/// A reset that doesn't say whether to keep the attempt's times first waits
/// for the commands already running to finish, including their `report`;
/// commands that arrive from then until its own result has been reported get
/// Busy without waiting, whether or not it has to ask. So `report` must return
/// promptly and not wait on other commands: waiting on such a reset would
/// deadlock, and a command sent during that reset's own `report` gets Busy.
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

// Swift's `EventSink` is `@unchecked Sendable` on the strength of this.
const _: () = {
    const fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<LsoCommandSink>();
};

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
/// timer, so the caller may drop theirs. `timer` must be a valid handle.
#[unsafe(no_mangle)]
pub extern "C" fn LsoCommandSink_new(timer: &SharedTimer, host: LsoHost) -> Box<LsoCommandSink> {
    Box::new(EventSink::new(timer.clone(), host))
}

/// Drops the sink and releases the host's context. `this` must be a valid sink.
#[unsafe(no_mangle)]
pub extern "C" fn LsoCommandSink_drop(this: Box<LsoCommandSink>) {
    drop(this);
}

/// Runs one server protocol message (UTF-8 JSON) and returns the reply.
/// Invalid UTF-8 is replaced, so it gets an `InvalidCommand` reply instead of
/// stopping the app. A null `command` is treated as empty.
///
/// # Safety
/// `this` is a valid sink, and `command` is null or a valid nul-terminated string.
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
/// since the last call. A null `data`, a zero size, a side or stride larger
/// than `MAX_SIDE` (16384), or a stride narrower than the width draws
/// nothing, and `data` isn't read.
///
/// # Safety
/// `this`, `layout_state` and `image_cache` are valid, and `data` is null or
/// valid for `stride * height * 4` bytes whenever that size can be drawn.
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
    let rendered = match render::image_len(width, height, stride) {
        Some(len) if !data.is_null() => {
            // SAFETY: the caller passes `len` valid bytes for a size that can
            // be drawn, and `len` is at most `isize::MAX`.
            let image = unsafe { std::slice::from_raw_parts_mut(data, len) };
            this.render(layout_state, image_cache, image, [width, height], stride)
        }
        _ => Rendered::NOTHING,
    };
    let [size_hint_width, size_hint_height] = rendered.size_hint.unwrap_or_default();
    LsoRendered {
        drew: rendered.drew,
        has_size_hint: rendered.size_hint.is_some(),
        size_hint_width,
        size_hint_height,
    }
}

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
            LsoRenderer_render(
                &mut renderer,
                &state,
                &cache,
                pixels.as_mut_ptr(),
                300,
                500,
                300,
            )
        };
        // SAFETY: as above.
        let second = unsafe {
            LsoRenderer_render(
                &mut renderer,
                &state,
                &cache,
                pixels.as_mut_ptr(),
                300,
                500,
                300,
            )
        };
        // SAFETY: a null buffer is allowed and draws nothing.
        let null = unsafe {
            LsoRenderer_render(
                &mut renderer,
                &state,
                &cache,
                std::ptr::null_mut(),
                300,
                500,
                300,
            )
        };

        assert!(first.drew && !first.has_size_hint);
        assert!(!second.drew);
        assert!(!null.drew);
        LsoRenderer_drop(renderer);
    }

    #[test]
    fn a_size_too_large_draws_nothing_through_the_c_function() {
        use crate::render::MAX_SIDE;
        use livesplit_core::{Lang, Layout, settings::ImageCache};

        let mut layout = Layout::default_layout(Lang::English);
        let mut cache = ImageCache::new();
        let state = layout.state(
            &mut cache,
            &timer(&["Time"]).read().unwrap().snapshot(),
            Lang::English,
        );
        let mut renderer = LsoRenderer_new();
        // A tiny buffer: the size is rejected before the buffer is used.
        let mut pixels = [0u8; 4];

        for (width, height, stride) in [
            (u32::MAX, u32::MAX, u32::MAX),
            (1, u32::MAX, u32::MAX),
            (MAX_SIDE + 1, 1, MAX_SIDE + 1),
            (1, MAX_SIDE + 1, 1),
            (1, 1, MAX_SIDE + 1),
            (2, 1, 1),
        ] {
            // SAFETY: valid objects; a size that can't be drawn doesn't read
            // the buffer.
            let rendered = unsafe {
                LsoRenderer_render(
                    &mut renderer,
                    &state,
                    &cache,
                    pixels.as_mut_ptr(),
                    width,
                    height,
                    stride,
                )
            };
            assert!(!rendered.drew, "{width} x {height}, stride {stride}");
            assert!(!rendered.has_size_hint);
        }
        LsoRenderer_drop(renderer);
    }
}
