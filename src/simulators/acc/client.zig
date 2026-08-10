//! Assetto Corsa Competizione client: opens the three shared-memory pages and exposes typed
//! struct snapshots via `physics()`, `graphics()`, and `static()`.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    OutOfMemory,
    Timeout,
    Canceled,
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
    phys_mem: core.transport.mmap.SharedMemory,
    gfx_mem: core.transport.mmap.SharedMemory,
    static_mem: core.transport.mmap.SharedMemory,
    has_static: bool,
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

        var has_static = true;
        var static_mem = core.transport.mmap.SharedMemory.open(.{
            .name = protocol.static_map_name,
            .size = @sizeOf(protocol.Static),
        }) catch blk: {
            has_static = false;
            break :blk core.transport.mmap.SharedMemory{};
        };
        errdefer static_mem.close();
        if (has_static and static_mem.view.len < @sizeOf(protocol.Static)) {
            has_static = false;
        }

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
            .has_static = has_static,
            .phys = phys,
            .gfx = gfx,
            .stat = stat,
        };
        _ = client.copyAll();
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.phys);
        self.allocator.destroy(self.gfx);
        self.allocator.destroy(self.stat);
        self.phys_mem.close();
        self.gfx_mem.close();
        if (self.has_static) self.static_mem.close();
    }

    pub fn liveStatus(self: *const Client) protocol.Status {
        const view = self.gfx_mem.view;
        if (view.len < 8) return .off;
        return @enumFromInt(std.mem.readInt(i32, view[4..8], .little));
    }

    pub fn livePhysicsPacketId(self: *const Client) i32 {
        return protocol.readPacketId(self.phys_mem.view) orelse 0;
    }

    pub fn isConnected(self: *const Client) bool {
        return self.liveStatus() != .off or self.livePhysicsPacketId() != 0;
    }

    pub fn poll(self: *Client) PollStatus {
        if (!self.isConnected()) return .disconnected;
        if (!self.copyAll()) return .stale;
        return .ok;
    }

    pub fn physics(self: *const Client) *const protocol.Physics {
        return self.phys;
    }

    pub fn graphics(self: *const Client) *const protocol.Graphics {
        return self.gfx;
    }

    pub fn static(self: *const Client) ?*const protocol.Static {
        return if (self.has_static) self.stat else null;
    }

    fn copyAll(self: *Client) bool {
        const ok_phys = copyPage(protocol.Physics, self.phys_mem.view, self.phys);
        const ok_gfx = copyPage(protocol.Graphics, self.gfx_mem.view, self.gfx);
        if (self.has_static) {
            const size = @sizeOf(protocol.Static);
            if (self.static_mem.view.len >= size) {
                @memcpy(std.mem.asBytes(self.stat), self.static_mem.view[0..size]);
            }
        }
        return ok_phys and ok_gfx;
    }
};

fn copyPage(comptime T: type, view: []const u8, dest: *T) bool {
    const size = @sizeOf(T);
    if (view.len < size) return false;
    var attempts: u8 = 0;
    while (attempts < 4) : (attempts += 1) {
        const begin = protocol.readPacketId(view) orelse return false;
        @memcpy(std.mem.asBytes(dest), view[0..size]);
        const end = protocol.readPacketId(view) orelse return false;
        if (begin == end) return true;
    }
    return false;
}

const builtin = @import("builtin");

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
    phys.rpm = 7300;
    const car = std.unicode.utf8ToUtf16LeStringLiteral("Ferrari 296 GT3");
    @memcpy(stat.car_model[0..car.len], car);
    const track = std.unicode.utf8ToUtf16LeStringLiteral("Spa");
    @memcpy(stat.track[0..track.len], track);

    var client = Client{
        .allocator = allocator,
        .phys_mem = .{},
        .gfx_mem = .{},
        .static_mem = .{},
        .has_static = true,
        .phys = phys,
        .gfx = gfx,
        .stat = stat,
    };

    try std.testing.expectApproxEqAbs(@as(f32, 211.0), client.physics().speed_kmh, 0.001);
    try std.testing.expectEqual(@as(i32, 7300), client.physics().rpm);
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ferrari 296 GT3", client.static().?.carModelUtf8(&buf).?);
    try std.testing.expectEqualStrings("Spa", client.static().?.trackUtf8(&buf).?);
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
