//! Assetto Corsa client: opens the three classic AC shared-memory pages and exposes typed
//! struct snapshots via `physics()`, `graphics()`, and `static()`.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    OutOfMemory,
};

pub const Client = struct {
    allocator: std.mem.Allocator,

    // Shared memory mappings.
    phys_mem: core.transport.mmap.SharedMemory,
    gfx_mem: core.transport.mmap.SharedMemory,
    static_mem: core.transport.mmap.SharedMemory,

    // Owned, torn-read-safe copies. Heap allocation keeps borrows valid if Client is moved.
    phys: *protocol.Physics,
    gfx: *protocol.Graphics,
    stat: *protocol.Static,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var phys_mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.physics_map_name,
            .size = @sizeOf(protocol.Physics),
        });
        errdefer phys_mem.close();

        var gfx_mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.graphics_map_name,
            .size = @sizeOf(protocol.Graphics),
        });
        errdefer gfx_mem.close();

        var static_mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.static_map_name,
            .size = @sizeOf(protocol.Static),
        });
        errdefer static_mem.close();

        const phys = try allocator.create(protocol.Physics);
        errdefer allocator.destroy(phys);
        const gfx = try allocator.create(protocol.Graphics);
        errdefer allocator.destroy(gfx);
        const stat = try allocator.create(protocol.Static);
        errdefer allocator.destroy(stat);

        phys.* = .{};
        gfx.* = .{};
        stat.* = .{};

        var client = Client{
            .allocator = allocator,
            .phys_mem = phys_mem,
            .gfx_mem = gfx_mem,
            .static_mem = static_mem,
            .phys = phys,
            .gfx = gfx,
            .stat = stat,
        };
        _ = client.copy();
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.phys);
        self.allocator.destroy(self.gfx);
        self.allocator.destroy(self.stat);
        self.phys_mem.close();
        self.gfx_mem.close();
        self.static_mem.close();
    }

    // Status according to the most recent graphics snapshot.
    pub fn status(self: *const Client) protocol.Status {
        return self.gfx.status();
    }

    /// Copy fresh physics/graphics/static snapshots from shared memory.
    pub fn poll(self: *Client) core.types.PollStatus {
        if (self.status() == .off) return .disconnected;
        if (!self.copy()) return .stale;
        return .ok;
    }

    /// Typed view of the most recent physics snapshot.
    pub fn physics(self: *const Client) *const protocol.Physics {
        return self.phys;
    }

    /// Typed view of the most recent graphics snapshot.
    pub fn graphics(self: *const Client) *const protocol.Graphics {
        return self.gfx;
    }

    /// Typed view of the static session metadata, or null when that page is unavailable.
    pub fn static(self: *const Client) ?*const protocol.Static {
        return self.stat;
    }

    fn copy(self: *Client) bool {
        const ok_phys = copyPage(protocol.Physics, self.phys_mem.view, self.phys, true);
        const ok_gfx = copyPage(protocol.Graphics, self.gfx_mem.view, self.gfx, true);
        const ok_stat = copyPage(protocol.Static, self.static_mem.view, self.stat, false);

        return ok_phys and ok_gfx and ok_stat;
    }
};

/// `packetId` lives at offset 0 of both live pages; read it without a full struct copy.
fn readPacketId(view: []const u8) ?i32 {
    if (view.len < 4) return null;
    return std.mem.readInt(i32, view[0..4], .little);
}

/// Copy a page into `dest`, retrying while `packetId` changes mid-copy (torn read).
fn copyPage(comptime T: type, view: []const u8, dest: *T, verify: bool) bool {
    const MAX_RETRIES = 5;

    const size = @sizeOf(T);
    if (view.len < size) return false;

    if (!verify) {
        @memcpy(std.mem.asBytes(dest), view[0..size]);
        return true;
    }

    for (0..MAX_RETRIES) |_| {
        const begin = readPacketId(view) orelse return false;
        @memcpy(std.mem.asBytes(dest), view[0..size]);
        const end = readPacketId(view) orelse return false;
        if (begin == end) return true;
    }

    return false;
}

const builtin = @import("builtin");

test "copyPage transfers a consistent snapshot" {
    var src: protocol.Physics = .{};
    src.packet_id = 7;
    src.speed_kmh = 88.5;
    src.gear = 3;

    var dest: protocol.Physics = undefined;
    try std.testing.expect(copyPage(protocol.Physics, std.mem.asBytes(&src), &dest, true));
    try std.testing.expectEqual(@as(i32, 3), dest.gear);
    try std.testing.expectApproxEqAbs(@as(f32, 88.5), dest.speed_kmh, 0.001);
}

test "copyPage rejects a short view" {
    var dest: protocol.Physics = undefined;
    var tiny: [4]u8 = .{ 0, 0, 0, 0 };
    try std.testing.expect(!copyPage(protocol.Physics, &tiny, &dest, true));
}

test "typed snapshot access and wstring decode" {
    const allocator = std.testing.allocator;
    const phys = try allocator.create(protocol.Physics);
    defer allocator.destroy(phys);
    const gfx = try allocator.create(protocol.Graphics);
    defer allocator.destroy(gfx);
    const stat = try allocator.create(protocol.Static);
    defer allocator.destroy(stat);

    phys.* = .{};
    gfx.* = .{};
    stat.* = .{};
    phys.speed_kmh = 211.0;
    phys.gear = 5;
    gfx.wind_speed = 4.5;
    const car = std.unicode.utf8ToUtf16LeStringLiteral("Ferrari 458");
    @memcpy(stat.car_model[0..car.len], car);
    const track = std.unicode.utf8ToUtf16LeStringLiteral("Monza");
    @memcpy(stat.track[0..track.len], track);

    var client = Client{
        .allocator = allocator,
        .phys_mem = .{},
        .gfx_mem = .{},
        .static_mem = .{},
        .phys = phys,
        .gfx = gfx,
        .stat = stat,
    };

    try std.testing.expectApproxEqAbs(@as(f32, 211.0), client.physics().speed_kmh, 0.001);
    try std.testing.expectEqual(@as(i32, 5), client.physics().gear);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), client.graphics().wind_speed, 0.001);

    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ferrari 458", client.static().?.carModelUtf8(&buf).?);
    try std.testing.expectEqualStrings("Monza", client.static().?.trackUtf8(&buf).?);
}

test "connect handles available or missing shared memory" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var c = client;
        c.deinit();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed => {},
        else => return err,
    }
}

test "readPacketId reads the leading counter" {
    var phys: protocol.Physics = .{};
    phys.packet_id = 99;
    try std.testing.expectEqual(@as(i32, 99), readPacketId(std.mem.asBytes(&phys)).?);
}
