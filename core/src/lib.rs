//! lso-core: livesplit-core's C API plus the functions a native app needs that
//! the C API only offers on the web (spec §5.3).

pub mod ffi;
pub mod protocol;
pub mod sink;
