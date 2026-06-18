//! librace — SDK for racing simulator telemetry.
//!
//! Import `librace.core` for shared types and transport helpers.
//! Import `librace.simulators` (or a specific simulator module) for per-title APIs.

const std = @import("std");

pub const core = @import("core/root.zig");
pub const simulators = @import("simulators/root.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(simulators.iracing);
    _ = @import("core/transport/mmap.zig");
}
