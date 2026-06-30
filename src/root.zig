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
    std.testing.refAllDecls(simulators.ac);
    std.testing.refAllDecls(simulators.acc);
    std.testing.refAllDecls(simulators.ace);
    std.testing.refAllDecls(simulators.acr);
    std.testing.refAllDecls(simulators.fh6);
    std.testing.refAllDecls(simulators.lmu);
    _ = @import("core/transport/mmap.zig");
    _ = @import("core/transport/udp.zig");
}
