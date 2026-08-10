//! Forza Horizon 6 client: binds a UDP listener and exposes typed access to the latest
//! 324-byte Data Out packet via `packet()`.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.udp.UdpListener.OpenError;
pub const PollError = error{Canceled};

pub const PollStatus = enum {
    ok,
    disconnected,
    stale,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

pub const Config = struct {
    address: []const u8 = "0.0.0.0",
    port: u16 = protocol.default_port,
};

pub const ConnectOptions = struct {
    config: Config = .{},
};

pub const Client = struct {
    listener: core.transport.udp.UdpListener,
    snapshot: protocol.DashPacket = .{},
    recv_buf: [protocol.packet_size]u8 = undefined,

    pub fn connect(io: std.Io, config: Config) ConnectError!Client {
        var listener = try core.transport.udp.UdpListener.open(io, .{
            .address = config.address,
            .port = config.port,
        });
        errdefer listener.close(io);

        return .{
            .listener = listener,
        };
    }

    pub fn deinit(self: *Client, io: std.Io) void {
        self.listener.close(io);
    }

    /// Receives until a valid datagram arrives, then copies it into the snapshot.
    ///
    /// `timeout` is currently unused: Zig 0.16 `receiveTimeout` returns
    /// `ConcurrencyUnavailable` for UDP on Windows. Use blocking receive for
    /// now; switch back to `listener.recv(..., timeout)` when std supports it
    /// (see `core/transport/udp.zig`).
    pub fn poll(self: *Client, io: std.Io, timeout: std.Io.Timeout) PollError!PollStatus {
        _ = timeout;
        while (true) {
            const msg = self.listener.socket.receive(io, &self.recv_buf) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => return .disconnected,
            };
            if (protocol.decodePacket(msg.data, &self.snapshot)) return .ok;
        }
    }

    pub fn packet(self: *const Client) *const protocol.DashPacket {
        return &self.snapshot;
    }
};

test "typed packet snapshot access" {
    var client = Client{
        .listener = undefined,
    };
    client.snapshot.speed = 50;
    client.snapshot.current_engine_rpm = 7200;
    client.snapshot.gear = 5;

    try std.testing.expectApproxEqAbs(@as(f32, 50), client.packet().speed, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 180), client.packet().speedKmh(), 0.001);
    try std.testing.expectEqual(@as(f32, 7200), client.packet().current_engine_rpm);
    try std.testing.expectEqual(@as(i32, 5), client.packet().displayGear());
}
