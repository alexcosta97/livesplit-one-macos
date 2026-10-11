// The functions core/ adds to livesplit-core's C API (spec §5.3).
// Implemented in core/src/ffi.rs. Keep the two in sync.
#ifndef LSO_CORE_H
#define LSO_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The app's callbacks for a command sink. `context` is passed to each one;
/// `release` is called once when the sink is dropped. Callbacks may run on any
/// thread that runs a command. All three callbacks must be non-null.
///
/// A callback must not call `LsoCommandSink_handle_command` (on any sink) on
/// the thread it runs on, for example from `report`: that would abort the app.
/// Dispatch to another thread or queue asynchronously instead.
///
/// A reset that doesn't say whether to keep the attempt's times first waits
/// for the commands already running to finish, including their `report`;
/// commands that arrive from then until its own result has been reported get
/// Busy without waiting, whether or not it has to ask. So `report` must return
/// promptly and not wait on other commands: waiting on such a reset would
/// deadlock, and a command sent during that reset's own `report` gets Busy.
typedef struct LsoHost {
    void *context;
    /// Each command's result: an event number (0 or more), or `-1 - error`.
    void (*report)(void *context, int32_t result);
    /// 0 keeps the attempt's times, 1 discards them, anything else doesn't reset.
    uint8_t (*decide_reset)(void *context);
    void (*release)(void *context);
} LsoHost;

/// Creates a command sink for a `SharedTimer`. The sink keeps its own handle.
/// `timer` must be a valid, non-null `SharedTimer` handle.
void *LsoCommandSink_new(void *timer, LsoHost host);
/// Drops the sink and calls `release`. `self` must be a valid, non-null sink.
void LsoCommandSink_drop(void *self);
/// Runs one server protocol message. `self` must be a valid, non-null sink;
/// `command` may be NULL (treated as empty). The reply stays valid until the next call
/// on the same thread.
char const *LsoCommandSink_handle_command(void *self, char const *command);
/// Encodes an event for the server. Valid until the next call on the thread.
char const *LsoServerProtocol_encode_event(uint32_t event);

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

#ifdef __cplusplus
}
#endif

#endif
