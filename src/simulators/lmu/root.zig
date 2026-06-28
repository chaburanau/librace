//! Le Mans Ultimate telemetry via the native Studio 397 shared-memory interface.
//!
//! Transport: memory-mapped file (`LMU_Data` on Windows).
//! Protocol: official LMU shared-memory SDK headers shipped under `Support/SharedMemoryInterface`.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");
pub const catalog = @import("catalog.zig");
pub const keys = @import("keys.zig");

pub const name = "Le Mans Ultimate";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const FieldRaw = client.FieldRaw;
pub const FieldHandle = client.FieldHandle;
pub const FieldDescriptor = client.FieldDescriptor;
pub const NameIterator = client.NameIterator;

pub const mem_map_name = protocol.mem_map_name;
pub const data_event_name = protocol.data_event_name;

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
