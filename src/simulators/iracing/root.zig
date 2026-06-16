//! iRacing telemetry via the iRacing SDK shared-memory interface.
//!
//! Transport: memory-mapped file (`Local\\IRSDKMem` on Windows).
//! Status: not yet implemented.

const core = @import("../../core/root.zig");

pub const name = "iRacing";
pub const transport = core.types.TransportKind.memory_mapped;
