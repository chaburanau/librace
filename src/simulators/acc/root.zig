//! Assetto Corsa Competizione telemetry via Windows shared memory.
//!
//! Transport: ACC reuses classic Assetto Corsa's three-page shared-memory model.
//! Design: typed struct snapshots via `physics()`, `graphics()`, and `static()`.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");

pub const name = "Assetto Corsa Competizione";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;

pub const Physics = protocol.Physics;
pub const Graphics = protocol.Graphics;
pub const Static = protocol.Static;
pub const Status = protocol.Status;
pub const SessionType = protocol.SessionType;
pub const FlagType = protocol.FlagType;
pub const PenaltyType = protocol.PenaltyType;
pub const TrackGripStatus = protocol.TrackGripStatus;
pub const RainIntensity = protocol.RainIntensity;

pub const physics_map_name = protocol.physics_map_name;
pub const graphics_map_name = protocol.graphics_map_name;
pub const static_map_name = protocol.static_map_name;
pub const field_count = protocol.field_count;

pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
    return Client.connect(allocator);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
