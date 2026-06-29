//! Forza Horizon 6 client: binds a UDP listener and exposes typed plus generic
//! access to the latest 324-byte Data Out packet.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");
const catalog = @import("catalog.zig");

pub const ConnectError = core.transport.udp.UdpListener.OpenError || error{
    OutOfMemory,
    Timeout,
    RecvFailed,
};

pub const PollStatus = enum {
    ok,
    disconnected,
    stale,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

pub const FieldRaw = struct {
    field_type: catalog.FieldType,
    count: usize,
    data: []const u8,
};

pub const FieldHandle = struct {
    descriptor: catalog.FieldDescriptor,
};

pub const NameIterator = catalog.NameIterator;
pub const FieldDescriptor = catalog.FieldDescriptor;

pub const Config = struct {
    address: []const u8 = "0.0.0.0",
    port: u16 = protocol.default_port,
    /// No UDP packet received for this many milliseconds ⇒ disconnected.
    stale_threshold_ms: u32 = 3000,
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

    pub fn connect(allocator: std.mem.Allocator, io: std.Io) ConnectError!Client {
        return connectWithConfig(allocator, io, .{});
    }

    pub fn connectWithConfig(
        allocator: std.mem.Allocator,
        io: std.Io,
        config: Config,
    ) ConnectError!Client {
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

    /// Retry until a valid packet arrives or `timeout_ms` elapses (`null` = forever).
    pub fn waitForConnection(
        allocator: std.mem.Allocator,
        io: std.Io,
        timeout_ms: ?u32,
    ) ConnectError!Client {
        return waitForConnectionWithConfig(allocator, io, .{}, timeout_ms);
    }

    pub fn waitForConnectionWithConfig(
        allocator: std.mem.Allocator,
        io: std.Io,
        config: Config,
        timeout_ms: ?u32,
    ) ConnectError!Client {
        var client = try connectWithConfig(allocator, io, config);
        errdefer client.deinit();

        std.debug.print(
            "Listening for FH6 Data Out on UDP {s}:{d} — start driving in-game (Data Out must match this port).\n",
            .{ config.address, config.port },
        );

        return waitForFirstPacket(&client, timeout_ms);
    }

    pub fn boundPort(self: *const Client) u16 {
        return self.listener.boundPort();
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.snapshot);
        self.listener.close(self.io);
    }

    pub fn isConnected(self: *const Client) bool {
        if (!self.has_packet) return false;
        return monotonicMs() -% self.last_recv_ms < self.config.stale_threshold_ms;
    }

    /// Blocks until a datagram arrives, then copies the latest valid packet into the snapshot.
    pub fn poll(self: *Client) PollStatus {
        while (true) {
            const msg = self.listener.recv(self.io, &self.recv_buf) catch return .disconnected;
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

    pub fn fieldCount(self: *const Client) usize {
        _ = self;
        return catalog.field_count;
    }

    pub fn hasField(self: *const Client, name: []const u8) bool {
        _ = self;
        return catalog.find(name) != null;
    }

    pub fn fieldNameIterator(self: *const Client) NameIterator {
        _ = self;
        return .{};
    }

    pub fn getNumber(self: *const Client, name: []const u8) ?f64 {
        const field = catalog.find(name) orelse return null;
        return catalog.decodeNumber(field, std.mem.asBytes(self.snapshot));
    }

    pub fn getRaw(self: *const Client, name: []const u8) ?FieldRaw {
        const field = catalog.find(name) orelse return null;
        const data = catalog.rawBytes(field, std.mem.asBytes(self.snapshot)) orelse return null;
        return .{ .field_type = field.field_type, .count = field.count, .data = data };
    }

    pub fn resolve(self: *const Client, name: []const u8) ?FieldHandle {
        _ = self;
        return .{ .descriptor = catalog.find(name) orelse return null };
    }

    pub fn read(self: *const Client, handle: FieldHandle) ?f64 {
        return catalog.decodeNumber(handle.descriptor, std.mem.asBytes(self.snapshot));
    }
};

/// Waits for the first valid packet using a receiver thread so the caller can
/// enforce `timeout_ms` while `UdpListener.recv` blocks.
fn waitForFirstPacket(client: *Client, timeout_ms: ?u32) ConnectError!Client {
    const recv_thread = std.Thread.spawn(.{}, recvWaitThread, .{client}) catch return error.RecvFailed;
    defer recv_thread.join();

    const step_ms: u32 = 50;
    var elapsed_ms: u32 = 0;
    while (!client.has_packet) {
        if (timeout_ms) |t| {
            if (elapsed_ms >= t) {
                client.listener.close(client.io);
                return error.Timeout;
            }
        }
        std.Io.sleep(client.io, std.Io.Duration.fromMilliseconds(step_ms), .real) catch {};
        elapsed_ms +|= step_ms;
    }
    return client.*;
}

fn recvWaitThread(client: *Client) void {
    while (!client.has_packet) {
        const msg = client.listener.recv(client.io, &client.recv_buf) catch return;
        if (protocol.decodePacket(msg.data, client.snapshot)) {
            client.has_packet = true;
            client.last_recv_ms = monotonicMs();
            return;
        }
    }
}

fn monotonicMs() u64 {
    if (@import("builtin").os.tag == .windows) {
        return GetTickCount64();
    }
    return @intCast(std.time.milliTimestamp());
}

extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;

test "generic access over an owned packet snapshot" {
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

    try std.testing.expectApproxEqAbs(@as(f64, 50), client.getNumber("speed").?, 0.001);
    try std.testing.expectEqual(@as(f64, 7200), client.getNumber("current_engine_rpm").?);
    try std.testing.expectEqual(@as(f64, 5), client.getNumber("gear").?);
}

test "connect binds a UDP listener" {
    var client = try Client.connect(std.testing.allocator, std.testing.io);
    defer client.deinit();
    try std.testing.expectEqual(protocol.default_port, client.boundPort());
}
