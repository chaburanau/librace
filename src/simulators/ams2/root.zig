//! Automobilista 2 telemetry via the official `$pcars2$` shared-memory API.
//!
//! Design: typed struct snapshot via `shared()`; participant grid via on-demand `participants()`.
//! Enable **Options → System → Shared Memory → Project CARS 2** in the game.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");

pub const name = "Automobilista 2";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;

pub const Shared = protocol.Shared;
pub const ParticipantInfo = protocol.ParticipantInfo;

pub const mem_map_name = protocol.mem_map_name;
pub const shared_memory_version = protocol.shared_memory_version;
pub const field_count = protocol.field_count;
pub const shared_size = protocol.shared_size;

pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
    return Client.connect(allocator);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
