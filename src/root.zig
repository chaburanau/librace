//! librace — SDK for racing simulator telemetry.
//!
//! Import `librace.core` for shared types and transport helpers.
//! Import `librace.simulators` (or a specific simulator module) for per-title APIs.
//! Import `librace.detect` to find which known sim process is running.
//! Import `librace.unified` for automatic lifecycle and normalized telemetry.

const std = @import("std");

pub const core = @import("core/root.zig");
pub const detect = @import("detector/root.zig");
pub const simulators = @import("simulators/root.zig");
pub const unified = @import("unifier/root.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(core);
    std.testing.refAllDecls(detect);
    std.testing.refAllDecls(unified);
    std.testing.refAllDecls(simulators.iracing);
    std.testing.refAllDecls(simulators.ac);
    std.testing.refAllDecls(simulators.acc);
    std.testing.refAllDecls(simulators.ace);
    std.testing.refAllDecls(simulators.acr);
    std.testing.refAllDecls(simulators.ams);
    std.testing.refAllDecls(simulators.ams2);
    std.testing.refAllDecls(simulators.beamng);
    std.testing.refAllDecls(simulators.fh6);
    std.testing.refAllDecls(simulators.lmu);
    std.testing.refAllDecls(simulators.r3e);
}
