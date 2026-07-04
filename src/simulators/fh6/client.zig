//! Forza Horizon 6 client: binds a UDP listener and exposes typed access to the latest
//! 324-byte Data Out packet via `packet()`.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.udp.UdpListener.OpenError || error{
    OutOfMemory,
    Timeout,
};

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
    /// No UDP packet received for this many milliseconds ⇒ disconnected.
    stale_threshold_ms: u32 = 3000,
};

pub const ConnectOptions = struct {
    config: Config = .{},
    /// Omitted/null means one bind attempt.
    timeout: ?std.Io.Duration = null,
    retry_interval: std.Io.Duration = std.Io.Duration.fromMilliseconds(50),
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    listener: core.transport.udp.UdpListener,
    config: Config,
    snapshot: *protocol.DashPacket,
    recv_buf: [protocol.packet_size]u8 = undefined,
    has_packet: bool = false,
    last_recv_ms: u64 = 0,

    pub fn connect(allocator: std.mem.Allocator, io: std.Io, config: Config) ConnectError!Client {
        var listener = try core.transport.udp.UdpListener.open(io, .{
            .address = config.address,
            .port = config.port,
        });
        errdefer listener.close(io);

        const snapshot = try allocator.create(protocol.DashPacket);
        errdefer allocator.destroy(snapshot);
        snapshot.* = .{};

        return .{
            .allocator = allocator,
            .io = io,
            .listener = listener,
            .config = config,
            .snapshot = snapshot,
        };
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.snapshot);
        self.listener.close(self.io);
    }

    pub fn isConnected(self: *const Client) bool {
        if (!self.has_packet) return false;
        return monotonicMs() -% self.last_recv_ms < self.config.stale_threshold_ms;
    }

    /// Waits up to `timeout` for a datagram, then copies the latest valid packet into the snapshot.
    pub fn poll(self: *Client, timeout: std.Io.Duration) PollStatus {
        while (true) {
            const msg = self.listener.recvTimeout(self.io, &self.recv_buf, timeout) catch |err| switch (err) {
                error.Timeout => return .stale,
                else => return .disconnected,
            };
            if (protocol.decodePacket(msg.data, self.snapshot)) {
                self.has_packet = true;
                self.last_recv_ms = monotonicMs();
                return .ok;
            }
        }
    }

    pub fn packet(self: *const Client) *const protocol.DashPacket {
        return self.snapshot;
    }
};

fn monotonicMs() u64 {
    if (@import("builtin").os.tag == .windows) {
        return GetTickCount64();
    }
    return @intCast(std.time.milliTimestamp());
}

extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;

test "typed packet snapshot access" {
    const allocator = std.testing.allocator;
    const snapshot = try allocator.create(protocol.DashPacket);
    defer allocator.destroy(snapshot);
    snapshot.* = .{};
    snapshot.speed = 50;
    snapshot.current_engine_rpm = 7200;
    snapshot.gear = 5;

    var client = Client{
        .allocator = allocator,
        .io = std.testing.io,
        .listener = undefined,
        .config = .{},
        .snapshot = snapshot,
        .has_packet = true,
    };

    try std.testing.expectApproxEqAbs(@as(f32, 50), client.packet().speed, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 180), client.packet().speedKmh(), 0.001);
    try std.testing.expectEqual(@as(f32, 7200), client.packet().current_engine_rpm);
    try std.testing.expectEqual(@as(i32, 4), client.packet().displayGear());
}
