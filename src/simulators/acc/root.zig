//! Assetto Corsa Competizione telemetry via Windows shared memory.
//!
//! Transport: ACC reuses classic Assetto Corsa's three-page shared-memory model:
//! `Local\\acpmf_physics` (high-rate vehicle dynamics), `Local\\acpmf_graphics`
//! (per-frame HUD/session state), and `Local\\acpmf_static` (session/car metadata).
//!
//! Design: fixed C structs with typed access (`physics()`, `graphics()`, `static()`) plus
//! generic name-based lookup (`getNumber`/`getString`/`getRaw`/`resolve`) and discovery
//! (`fieldNameIterator`) built from comptime reflection of the protocol structs.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");
pub const catalog = @import("catalog.zig");
pub const keys = @import("keys.zig");

pub const name = "Assetto Corsa Competizione";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const FieldRaw = client.FieldRaw;
pub const FieldHandle = client.FieldHandle;
pub const FieldDescriptor = client.FieldDescriptor;
pub const NameIterator = client.NameIterator;

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

pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
    return Client.connect(allocator);
}

/// Retry connecting until the sim is available or `timeout_ms` elapses (`null` = forever).
pub fn waitForConnection(
    allocator: std.mem.Allocator,
    io: std.Io,
    timeout_ms: ?u32,
) ConnectError!Client {
    return Client.waitForConnection(allocator, io, timeout_ms);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
    _ = @import("catalog.zig");
    _ = @import("keys.zig");
}
