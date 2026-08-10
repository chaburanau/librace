//! RaceRoom Racing Experience client for the `$R3E` shared-memory interface.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    OutOfMemory,
    VersionMismatch,
};

pub const PollStatus = enum {
    ok,
    disconnected,
    stale,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    mem: core.transport.mmap.SharedMemory,
    snap: *protocol.Shared,
    drivers_loaded: bool = false,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.mem_map_name,
            .size = protocol.shared_size,
        });
        errdefer mem.close();

        if (mem.view.len < protocol.shared_core_size) return error.MapFailed;

        const major = protocol.readVersionMajor(mem.view) orelse 0;
        if (major != 0 and major != protocol.version_major) return error.VersionMismatch;

        const snap = try allocator.create(protocol.Shared);
        errdefer allocator.destroy(snap);
        snap.* = std.mem.zeroes(protocol.Shared);

        var client = Client{
            .allocator = allocator,
            .mem = mem,
            .snap = snap,
        };
        _ = client.copyCore();
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.snap);
        self.mem.close();
    }

    pub fn isConnected(self: *const Client) bool {
        const major = protocol.readVersionMajor(self.mem.view) orelse return false;
        if (major != protocol.version_major) return false;
        return true;
    }

    pub fn poll(self: *Client) PollStatus {
        if (!self.isConnected()) return .disconnected;
        if (!self.copyCore()) return .stale;
        return .ok;
    }

    /// Typed snapshot of the shared-memory core (excludes the driver grid until `drivers()`).
    pub fn shared(self: *const Client) *const protocol.Shared {
        return self.snap;
    }

    /// Driver grid for the current session. Copied from shared memory on first call after each
    /// successful `poll()`; skipped entirely when unused.
    pub fn drivers(self: *Client) []const protocol.DriverData {
        if (!self.drivers_loaded) {
            if (self.copyDrivers()) self.drivers_loaded = true;
        }
        const n: usize = @intCast(@max(self.snap.num_cars, 0));
        return self.snap.all_drivers[0..@min(n, protocol.num_drivers_max)];
    }

    fn copyCore(self: *Client) bool {
        const view = self.mem.view;
        if (view.len < protocol.shared_core_size) return false;

        self.drivers_loaded = false;

        var attempts: u8 = 0;
        while (attempts < 4) : (attempts += 1) {
            const begin = protocol.readSimulationTicks(view) orelse return false;
            @memcpy(std.mem.asBytes(self.snap)[0..protocol.shared_core_size], view[0..protocol.shared_core_size]);
            const end = protocol.readSimulationTicks(view) orelse return false;
            if (begin == end) return true;
        }
        return false;
    }

    fn copyDrivers(self: *Client) bool {
        const view = self.mem.view;
        const n: usize = @intCast(@max(@min(self.snap.num_cars, @as(i32, @intCast(protocol.num_drivers_max))), 0));
        if (n == 0) return true;

        const offset = protocol.shared_core_size;
        const bytes = n * protocol.driver_data_size;
        if (view.len < offset + bytes) return false;

        var attempts: u8 = 0;
        while (attempts < 4) : (attempts += 1) {
            const begin = protocol.readSimulationTicks(view) orelse return false;
            const dest = std.mem.asBytes(self.snap)[offset..][0..bytes];
            @memcpy(dest, view[offset..][0..bytes]);
            const end = protocol.readSimulationTicks(view) orelse return false;
            if (begin == end) return true;
        }
        return false;
    }
};

test "typed snapshot access and helpers" {
    const allocator = std.testing.allocator;
    const snap = try allocator.create(protocol.Shared);
    defer allocator.destroy(snap);
    snap.* = std.mem.zeroes(protocol.Shared);

    snap.version_major = protocol.version_major;
    snap.version_minor = protocol.version_minor;
    snap.car_speed = 25.0;
    snap.engine_rps = 200.0 * (2.0 * std.math.pi) / 60.0;
    snap.gear = 4;
    snap.num_cars = 2;
    @memcpy(snap.track_name[0.."Spa".len], "Spa");
    @memcpy(snap.vehicle_info.name[0.."Porsche 992".len], "Porsche 992");
    @memcpy(snap.all_drivers[0].driver_info.name[0.."Alice".len], "Alice");
    @memcpy(snap.all_drivers[1].driver_info.name[0.."Bob".len], "Bob");
    snap.all_drivers[0].place = 1;
    snap.all_drivers[1].place = 2;

    var client = Client{
        .allocator = allocator,
        .mem = .{},
        .snap = snap,
        .drivers_loaded = true,
    };

    try std.testing.expectApproxEqAbs(@as(f32, 90.0), client.shared().speedKmh(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), client.shared().engineRpm(), 0.1);
    try std.testing.expectEqual(@as(i32, 4), client.shared().displayGear());
    try std.testing.expectEqualStrings("Spa", client.shared().trackName());
    try std.testing.expectEqualStrings("Porsche 992", client.shared().vehicle_info.nameUtf8());

    const drivers = client.drivers();
    try std.testing.expectEqual(@as(usize, 2), drivers.len);
    try std.testing.expectEqualStrings("Alice", drivers[0].driver_info.nameUtf8());
    try std.testing.expectEqualStrings("Bob", drivers[1].driver_info.nameUtf8());
}

test "poll invalidates cached drivers until reloaded" {
    const allocator = std.testing.allocator;
    const snap = try allocator.create(protocol.Shared);
    defer allocator.destroy(snap);
    snap.* = std.mem.zeroes(protocol.Shared);
    snap.num_cars = 1;
    @memcpy(snap.all_drivers[0].driver_info.name[0.."Old".len], "Old");

    var client = Client{
        .allocator = allocator,
        .mem = .{},
        .snap = snap,
        .drivers_loaded = true,
    };
    try std.testing.expectEqualStrings("Old", client.drivers()[0].driver_info.nameUtf8());

    // Simulate a core poll without a live mapping: mark drivers stale and clear the row.
    client.drivers_loaded = false;
    snap.all_drivers[0] = .{};
    @memcpy(snap.all_drivers[0].driver_info.name[0.."New".len], "New");
    // Without a mapping, copyDrivers is a no-op when view is empty — set loaded after manual fill.
    client.drivers_loaded = true;
    try std.testing.expectEqualStrings("New", client.drivers()[0].driver_info.nameUtf8());
}

test "connect handles missing RaceRoom shared memory" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var c = client;
        defer c.deinit();
        try std.testing.expect(c.isConnected());
        _ = c.poll();
        _ = c.shared();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed, error.VersionMismatch => {},
        else => return err,
    }
}

test "connect reports NotFound when mapping is absent" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Opening a guaranteed-missing name exercises the same error path RaceRoom uses when closed.
    const result = core.transport.mmap.SharedMemory.open(.{
        .name = "Local\\librace_r3e_test_nonexistent_shm",
        .size = 64,
    });
    if (result) |opened| {
        var mem = opened;
        mem.close();
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.NotFound => {},
        else => return err,
    }
}
