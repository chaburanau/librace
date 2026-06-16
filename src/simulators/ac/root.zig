//! Assetto Corsa telemetry via shared memory (AC shared memory plugin layout).
//!
//! Transport: memory-mapped file.
//! Status: not yet implemented.

const core = @import("../../core/root.zig");

pub const name = "Assetto Corsa";
pub const transport = core.types.TransportKind.memory_mapped;
