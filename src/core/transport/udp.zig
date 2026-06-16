//! UDP telemetry transport primitives.
//!
//! Some simulators broadcast telemetry over UDP (often alongside shared memory).
//! Per-simulator packet layouts and ports live in `simulators/`.

/// Placeholder for UDP listener configuration.
pub const Config = struct {
    /// Local bind address (e.g. `"0.0.0.0"`).
    address: []const u8 = "0.0.0.0",
    /// UDP port to listen on.
    port: u16,
};
