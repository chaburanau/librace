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
pub const ConnectOptions = client.ConnectOptions;
pub const FieldRaw = client.FieldRaw;
pub const FieldHandle = client.FieldHandle;
pub const FieldDescriptor = client.FieldDescriptor;
pub const NameIterator = client.NameIterator;

pub const DashPacket = protocol.DashPacket;
pub const CarClass = protocol.CarClass;
pub const DrivetrainType = protocol.DrivetrainType;
pub const default_port = protocol.default_port;
pub const packet_size = protocol.packet_size;

pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: ConnectOptions) ConnectError!Client {
    return core.connect.retry(Client, ConnectError, ConnectContext, io, .{
        .allocator = allocator,
        .io = io,
        .config = options.config,
    }, .{
        .timeout = options.timeout,
        .retry_interval = options.retry_interval,
    }, connectOnce, isRetryableConnectError);
}

const ConnectContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: Config,
};

fn connectOnce(ctx: ConnectContext) ConnectError!Client {
    return Client.connect(ctx.allocator, ctx.io, ctx.config);
}

fn isRetryableConnectError(err: ConnectError) bool {
    return switch (err) {
        error.AddressInUse => true,
        else => false,
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
    _ = @import("catalog.zig");
    _ = @import("keys.zig");
}
