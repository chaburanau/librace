//! Forza Horizon 6 telemetry via UDP "Data Out".
//!
//! Design: typed access to the latest packet via `packet()`.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");

pub const protocol = @import("protocol.zig");

pub const name = "Forza Horizon 6";
pub const transport = core.types.TransportKind.udp;

pub const ConnectError = client.ConnectError;
pub const PollError = client.PollError;
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const Config = client.Config;
pub const ConnectOptions = client.ConnectOptions;

pub const DashPacket = protocol.DashPacket;
pub const CarClass = protocol.CarClass;
pub const DrivetrainType = protocol.DrivetrainType;
pub const default_port = protocol.default_port;
pub const packet_size = protocol.packet_size;
pub const field_count = protocol.field_count;

pub fn connect(io: std.Io, options: ConnectOptions) ConnectError!Client {
    return Client.connect(io, options.config);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
}
