//! Le Mans Ultimate telemetry.
//!
//! Transport: expected shared memory (rF2 family); confirm during implementation.
//! Status: not yet implemented.

const core = @import("../../core/root.zig");

pub const name = "Le Mans Ultimate";
pub const transport = core.types.TransportKind.memory_mapped;
