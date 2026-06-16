//! Assetto Corsa Rally telemetry.
//!
//! Transport: expected shared memory (AC family); confirm during implementation.
//! Status: not yet implemented.

const core = @import("../../core/root.zig");

pub const name = "Assetto Corsa Rally";
pub const transport = core.types.TransportKind.memory_mapped;
