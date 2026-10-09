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
