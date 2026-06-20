//! Forza Horizon 6 client: binds a UDP listener and exposes typed plus generic
//! access to the latest 324-byte Data Out packet.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");
const catalog = @import("catalog.zig");

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
    listener: core.transport.udp.UdpListener,
    config: Config,
    snapshot: *protocol.DashPacket,
    recv_buf: [protocol.packet_size]u8 = undefined,
    has_packet: bool = false,
    last_recv_ms: u64 = 0,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        return connectWithConfig(allocator, .{});
    }

    pub fn connectWithConfig(allocator: std.mem.Allocator, config: Config) ConnectError!Client {
        var listener = try core.transport.udp.UdpListener.open(.{
            .address = config.address,
            .port = config.port,
        });
        errdefer listener.close();

        const snapshot = try allocator.create(protocol.DashPacket);
        errdefer allocator.destroy(snapshot);
        snapshot.* = .{};

        return .{
            .allocator = allocator,
            .listener = listener,
            .config = config,
            .snapshot = snapshot,
        };
    }

    /// Retry until a valid packet arrives or `timeout_ms` elapses (`null` = forever).
    pub fn waitForConnection(allocator: std.mem.Allocator, timeout_ms: ?u32) ConnectError!Client {
        return waitForConnectionWithConfig(allocator, .{}, timeout_ms);
    }

    pub fn waitForConnectionWithConfig(
        allocator: std.mem.Allocator,
        config: Config,
        timeout_ms: ?u32,
    ) ConnectError!Client {
        var client = try connectWithConfig(allocator, config);
        errdefer client.deinit();

        std.debug.print(
            "Listening for FH6 Data Out on UDP {s}:{d} — start driving in-game (Data Out must match this port).\n",
            .{ config.address, config.port },
        );

        const step_ms: u32 = 50;
        var elapsed_ms: u32 = 0;
        while (!client.has_packet) {
            _ = client.drainSocket();
            if (client.has_packet) return client;
            if (timeout_ms) |t| {
                if (elapsed_ms >= t) return error.Timeout;
            }
            sleepMs(step_ms);
            elapsed_ms +|= step_ms;
        }
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.snapshot);
        self.listener.close();
    }

    pub fn boundPort(self: *const Client) u16 {
        return self.listener.bound_port;
    }

    pub fn isConnected(self: *const Client) bool {
        if (!self.has_packet) return false;
        return monotonicMs() -% self.last_recv_ms < self.config.stale_threshold_ms;
    }

    /// Receive the latest datagram and copy it into the owned packet snapshot.
    pub fn poll(self: *Client) PollStatus {
        if (self.drainSocket()) return .ok;
        if (self.isConnected()) return .stale;
        return .disconnected;
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

    fn drainSocket(self: *Client) bool {
        var got = false;
        while (true) {
            const len = self.listener.tryRecv(&self.recv_buf) catch break;
            const n = len orelse break;
            if (protocol.decodePacket(self.recv_buf[0..n], self.snapshot)) {
                self.has_packet = true;
                self.last_recv_ms = monotonicMs();
                got = true;
            }
        }
        return got;
    }
};

fn monotonicMs() u64 {
    if (@import("builtin").os.tag == .windows) {
        return GetTickCount64();
    }
    return 0;
}

fn sleepMs(ms: u32) void {
    if (@import("builtin").os.tag == .windows) {
        Sleep(ms);
    }
}

extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

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
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var client = try Client.connect(std.testing.allocator);
    defer client.deinit();
    try std.testing.expectEqual(protocol.default_port, client.boundPort());
}
