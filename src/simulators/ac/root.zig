//! Assetto Corsa telemetry via Windows shared memory.
//!
//! Transport: the classic Assetto Corsa three-page model — `Local\\acpmf_physics` (high-rate
//! vehicle dynamics), `Local\\acpmf_graphics` (per-frame HUD/session state), and
//! `Local\\acpmf_static` (session/car metadata, written once on load).
//!
//! Design: fixed C structs. The client exposes typed struct access via `physics()`,
//! `graphics()`, and `static()`. UTF-16 string fields decode through helpers on the protocol
//! structs (for example `Static.trackUtf8`).

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");
const protocol = @import("protocol.zig");

pub const Client = client.Client;
pub const ConnectError = client.ConnectError;

pub const Physics = protocol.Physics;
pub const Graphics = protocol.Graphics;
pub const Static = protocol.Static;
pub const Status = protocol.Status;
pub const SessionType = protocol.SessionType;
pub const FlagType = protocol.FlagType;

pub const name = "Assetto Corsa";
pub const transport = core.types.TransportKind.mmap;
pub const physics_map_name = protocol.physics_map_name;
pub const graphics_map_name = protocol.graphics_map_name;
pub const static_map_name = protocol.static_map_name;

pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
    return Client.connect(allocator);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
