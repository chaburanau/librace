//! iRacing telemetry via the iRacing SDK shared-memory interface.
//!
//! Transport: memory-mapped file (`Local\\IRSDKMemMapFileName` on Windows).
//! Protocol: IRSDK v2 — variable catalog + triple-buffered telemetry rows.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");
pub const session = @import("session.zig");
pub const catalog = @import("catalog.zig");
pub const keys = @import("keys.zig");

pub const name = "iRacing";
pub const transport = core.types.TransportKind.memory_mapped;

pub const ConnectError = client.ConnectError;
pub const GetError = client.GetError;
pub const CoerceError = client.CoerceError;
pub const ReadError = client.ReadError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const VarValue = client.VarValue;
pub const VarRaw = client.VarRaw;
pub const VarDescriptor = client.VarDescriptor;
pub const VarHandle = client.VarHandle;
pub const Binding = client.Binding;
pub const VarNameIterator = client.VarNameIterator;
pub const SessionSectionIterator = client.SessionSectionIterator;

pub const mem_map_name = protocol.mem_map_name;

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
    _ = @import("session.zig");
    _ = @import("catalog.zig");
    _ = @import("keys.zig");
}
