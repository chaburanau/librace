//! RaceRoom Racing Experience telemetry via the official `$R3E` shared-memory API.
//!
//! Design: typed struct snapshot via `shared()`; driver grid via on-demand `drivers()`.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");

pub const name = "RaceRoom Racing Experience";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const ConnectOptions = core.connect.Options;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;

pub const Shared = protocol.Shared;
pub const PlayerData = protocol.PlayerData;
pub const DriverData = protocol.DriverData;
pub const DriverInfo = protocol.DriverInfo;

pub const mem_map_name = protocol.mem_map_name;
pub const version_major = protocol.version_major;
pub const version_minor = protocol.version_minor;
pub const field_count = protocol.field_count;
pub const shared_size = protocol.shared_size;
pub const shared_core_size = protocol.shared_core_size;

pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: ConnectOptions) ConnectError!Client {
    return core.connect.retry(Client, ConnectError, std.mem.Allocator, io, allocator, options, Client.connect, isRetryableConnectError);
}

fn isRetryableConnectError(err: ConnectError) bool {
    return switch (err) {
        error.NotFound, error.MapFailed => true,
        else => false,
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
