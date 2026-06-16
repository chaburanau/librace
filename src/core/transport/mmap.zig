//! Memory-mapped file / shared-memory transport primitives.
//!
//! Many simulators (iRacing, AC family) expose telemetry through OS shared memory
//! or memory-mapped files. Per-simulator layout and parsing live in `simulators/`.

/// Placeholder for shared-memory connection configuration.
pub const Config = struct {
    /// Platform-specific name or path (e.g. `"Local\\IRSDKMem"` on Windows).
    name: []const u8,
};
