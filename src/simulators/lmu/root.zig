//! Le Mans Ultimate telemetry via the native Studio 397 shared-memory interface.
//!
//! Design: typed struct snapshots via `telemetry()`, `session()`, and `vehicle()`.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");

pub const name = "Le Mans Ultimate";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const ConnectOptions = core.connect.Options;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;

pub const TelemInfoV01 = protocol.TelemInfoV01;
pub const ScoringInfoV01 = protocol.ScoringInfoV01;
pub const VehicleScoringInfoV01 = protocol.VehicleScoringInfoV01;

pub const mem_map_name = protocol.mem_map_name;
pub const data_event_name = protocol.data_event_name;
pub const field_count = protocol.field_count;

pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: ConnectOptions) ConnectError!Client {
    return core.connect.retry(Client, ConnectError, std.mem.Allocator, io, allocator, options, Client.connect, isRetryableConnectError);
}

fn isRetryableConnectError(err: ConnectError) bool {
    return switch (err) {
        error.NotFound, error.InvalidData => true,
        else => false,
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
