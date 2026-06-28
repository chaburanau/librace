//! Assetto Corsa Evo telemetry via Windows shared memory.
//!
//! Transport: three memory-mapped pages — `Local\\acevo_pmf_physics` (high-rate vehicle
//! dynamics), `Local\\acevo_pmf_graphics` (per-frame HUD/session state), and
//! `Local\\acevo_pmf_static` (session metadata, written once on load).
//!
//! Design: fixed C structs (unlike iRacing's runtime variable catalog). The client exposes
//! typed struct access (`physics()`, `graphics()`, `static()`) plus generic name-based
//! lookup (`getNumber`/`getRaw`/`resolve`) and discovery (`fieldNameIterator`) built from a
//! comptime reflection of the protocol structs. Optional `keys.zig` provides common names.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");
pub const catalog = @import("catalog.zig");
pub const keys = @import("keys.zig");

pub const name = "Assetto Corsa Evo";
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
pub const CarLocation = protocol.CarLocation;

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
