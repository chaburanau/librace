//! Forza Horizon 6 telemetry via UDP "Data Out".
//!
//! Transport: the game sends fixed 324-byte datagrams to a configured IP/port while
//! the player is actively driving. Enable under Settings → HUD and Gameplay → Data Out.
//!
//! Design: typed access to the latest packet (`packet()`) plus generic name-based lookup
//! (`getNumber`/`getRaw`/`resolve`) and discovery (`fieldNameIterator`).

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");
pub const catalog = @import("catalog.zig");
pub const keys = @import("keys.zig");

pub const name = "Forza Horizon 6";
pub const transport = core.types.TransportKind.udp;

pub const ConnectError = client.ConnectError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const Config = client.Config;
pub const FieldRaw = client.FieldRaw;
pub const FieldHandle = client.FieldHandle;
pub const FieldDescriptor = client.FieldDescriptor;
pub const NameIterator = client.NameIterator;

pub const DashPacket = protocol.DashPacket;
pub const CarClass = protocol.CarClass;
pub const DrivetrainType = protocol.DrivetrainType;
pub const default_port = protocol.default_port;
pub const packet_size = protocol.packet_size;

pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
    return Client.connect(allocator);
}

pub fn connectWithConfig(allocator: std.mem.Allocator, config: Config) ConnectError!Client {
    return Client.connectWithConfig(allocator, config);
}

pub fn waitForConnection(allocator: std.mem.Allocator, timeout_ms: ?u32) ConnectError!Client {
    return Client.waitForConnection(allocator, timeout_ms);
}

pub fn waitForConnectionWithConfig(
    allocator: std.mem.Allocator,
    config: Config,
    timeout_ms: ?u32,
) ConnectError!Client {
    return Client.waitForConnectionWithConfig(allocator, config, timeout_ms);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
    _ = @import("catalog.zig");
    _ = @import("keys.zig");
}
