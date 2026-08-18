//! Automatic simulator detection and normalized telemetry access.
//!
//! The unified layer is an opt-in common subset. Per-title modules remain the
//! complete, native telemetry API.

const std = @import("std");

pub const types = @import("types.zig");
pub const Manager = @import("manager.zig").Manager;
pub const NativeClient = @import("manager.zig").NativeClient;
pub const UpdateError = @import("manager.zig").UpdateError;

pub const Options = types.Options;
pub const UpdateStatus = types.UpdateStatus;

test {
    std.testing.refAllDecls(@This());
    _ = @import("types.zig");
    _ = @import("manager.zig");
    _ = @import("adapters.zig");
}
