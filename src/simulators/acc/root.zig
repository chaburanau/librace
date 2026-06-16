//! Assetto Corsa Competizione telemetry.
//!
//! Transport: shared memory and UDP (broadcast).
//! Status: not yet implemented.

const core = @import("../../core/root.zig");

pub const name = "Assetto Corsa Competizione";
pub const transport = core.types.TransportKind.hybrid;
