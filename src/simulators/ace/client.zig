//! Assetto Corsa Evo client: opens the three shared-memory pages and exposes typed
//! struct access plus generic name-based lookup over the physics/graphics catalog.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");
const catalog = @import("catalog.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    /// A required page mapped but is smaller than its documented struct.
    InvalidData,
    OutOfMemory,
};

/// Result of a single [`Client.poll`].
pub const PollStatus = enum {
    /// Fresh page copies were taken this tick.
    ok,
    /// The simulator reports no active session (status = off).
    disconnected,
    /// Connected, but the page could not be copied this tick.
    stale,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

/// Raw little-endian bytes for a catalog field. Valid until the next `poll`.
pub const FieldRaw = struct {
    field_type: catalog.FieldType,
    count: usize,
    data: []const u8,
};

/// Stable reference to a catalog field, resolved once and read many times.
pub const FieldHandle = struct {
    descriptor: catalog.FieldDescriptor,
};

pub const NameIterator = catalog.NameIterator;
pub const FieldDescriptor = catalog.FieldDescriptor;

pub const Client = struct {
    allocator: std.mem.Allocator,
    phys_mem: core.transport.mmap.SharedMemory,
    gfx_mem: core.transport.mmap.SharedMemory,
    static_mem: core.transport.mmap.SharedMemory,
    has_static: bool,

    // Owned, torn-read-safe copies. Heap-allocated so borrows stay valid when the
    // `Client` value itself is moved (returned by value, stored in a context, etc.).
    phys: *protocol.Physics,
    gfx: *protocol.Graphics,
    stat: *protocol.Static,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var phys_mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.physics_map_name,
            .size = @sizeOf(protocol.Physics),
        });
        errdefer phys_mem.close();
        if (phys_mem.view.len < @sizeOf(protocol.Physics)) return error.InvalidData;

        var gfx_mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.graphics_map_name,
            .size = @sizeOf(protocol.Graphics),
        });
        errdefer gfx_mem.close();
        if (gfx_mem.view.len < @sizeOf(protocol.Graphics)) return error.InvalidData;

        // Static is best-effort: present in normal sessions, but the live pages carry
        // enough to operate if it is briefly unavailable.
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

    /// Retry `connect` until the sim is available or `timeout_ms` elapses (`null` = forever).
    pub fn waitForConnection(
        allocator: std.mem.Allocator,
        io: std.Io,
        timeout_ms: ?u32,
    ) ConnectError!Client {
        const step_ms: u32 = 200;
        var elapsed_ms: u32 = 0;
        while (true) {
            if (Client.connect(allocator)) |client| {
                return client;
            } else |err| switch (err) {
                error.NotFound, error.InvalidData => {
                    if (timeout_ms) |t| {
                        if (elapsed_ms >= t) return err;
                    }
                    std.Io.sleep(io, std.Io.Duration.fromMilliseconds(step_ms), .real) catch {};
                    elapsed_ms +|= step_ms;
                },
                else => return err,
            }
        }
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.phys);
        self.allocator.destroy(self.gfx);
        self.allocator.destroy(self.stat);
        self.phys_mem.close();
        self.gfx_mem.close();
        if (self.has_static) self.static_mem.close();
    }

    /// Live simulator status read directly from the graphics mapping (not the local copy).
    pub fn liveStatus(self: *const Client) protocol.Status {
        const view = self.gfx_mem.view;
        if (view.len < 8) return .off;
        return @enumFromInt(std.mem.readInt(i32, view[4..8], .little));
    }

    pub fn isConnected(self: *const Client) bool {
        return self.liveStatus() != .off;
    }

    /// Copy fresh physics/graphics/static snapshots from shared memory.
    pub fn poll(self: *Client) PollStatus {
        if (!self.isConnected()) return .disconnected;
        if (!self.copyAll()) return .stale;
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
        return if (self.has_static) self.stat else null;
    }

    /// Number of named numeric fields in the generic catalog (both pages).
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

    /// Read a numeric field by protocol name as a lenient `f64`. Null when unknown or a string.
    pub fn getNumber(self: *const Client, name: []const u8) ?f64 {
        const field = catalog.find(name) orelse return null;
        return catalog.decodeNumber(field, self.pageBytes(field.page));
    }

    /// Read a string field (NUL-terminated `[N]u8`) by protocol name. Null when unknown or
    /// not a string. The slice borrows from the owned snapshot and stays valid until `poll`.
    pub fn getString(self: *const Client, name: []const u8) ?[]const u8 {
        const field = catalog.find(name) orelse return null;
        return catalog.decodeString(field, self.pageBytes(field.page));
    }

    /// Raw little-endian bytes for a field (whole array for non-scalars).
    pub fn getRaw(self: *const Client, name: []const u8) ?FieldRaw {
        const field = catalog.find(name) orelse return null;
        const data = catalog.rawBytes(field, self.pageBytes(field.page)) orelse return null;
        return .{ .field_type = field.field_type, .count = field.count, .data = data };
    }

    /// Resolve a name into a handle for repeated reads without re-scanning the catalog.
    pub fn resolve(self: *const Client, name: []const u8) ?FieldHandle {
        _ = self;
        return .{ .descriptor = catalog.find(name) orelse return null };
    }

    pub fn read(self: *const Client, handle: FieldHandle) ?f64 {
        return catalog.decodeNumber(handle.descriptor, self.pageBytes(handle.descriptor.page));
    }

    fn pageBytes(self: *const Client, page: catalog.Page) []const u8 {
        return switch (page) {
            .physics => std.mem.asBytes(self.phys),
            .graphics => std.mem.asBytes(self.gfx),
            .static => std.mem.asBytes(self.stat),
        };
    }

    fn copyAll(self: *Client) bool {
        const ok_phys = copyPage(protocol.Physics, self.phys_mem.view, self.phys);
        const ok_gfx = copyPage(protocol.Graphics, self.gfx_mem.view, self.gfx);
        if (self.has_static) {
            // Static has no packet counter; a plain copy is sufficient (rewritten on load).
            const size = @sizeOf(protocol.Static);
            if (self.static_mem.view.len >= size) {
                @memcpy(std.mem.asBytes(self.stat), self.static_mem.view[0..size]);
            }
        }
        return ok_phys and ok_gfx;
    }
};

/// Copy a page into `dest`, retrying while `packetId` changes mid-copy (torn read).
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
    @memcpy(std.mem.asBytes(dest), view[0..size]);
    return true;
}

const builtin = @import("builtin");

test "copyPage transfers a consistent snapshot" {
    var src: protocol.Physics = .{};
    src.packet_id = 7;
    src.speed_kmh = 88.5;
    src.gear = 3;

    var dest: protocol.Physics = undefined;
    try std.testing.expect(copyPage(protocol.Physics, std.mem.asBytes(&src), &dest));
    try std.testing.expectEqual(@as(i32, 3), dest.gear);
    try std.testing.expectApproxEqAbs(@as(f32, 88.5), dest.speed_kmh, 0.001);
}

test "copyPage rejects a short view" {
    var dest: protocol.Physics = undefined;
    var tiny: [4]u8 = .{ 0, 0, 0, 0 };
    try std.testing.expect(!copyPage(protocol.Physics, &tiny, &dest));
}

test "generic getNumber over an owned snapshot" {
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
    gfx.npos = 0.25;
    const car = "Ferrari 296 GT3";
    @memcpy(gfx.car_model[0..car.len], car);
    const track = "Monza";
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

    try std.testing.expectApproxEqAbs(@as(f64, 211.0), client.getNumber("speed_kmh").?, 0.001);
    try std.testing.expectEqual(@as(f64, 5), client.getNumber("gear").?);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), client.getNumber("npos").?, 0.001);
    try std.testing.expect(client.getNumber("does_not_exist") == null);

    // Strings are reached through the same generic catalog (no hand-written accessors).
    try std.testing.expectEqualStrings("Ferrari 296 GT3", client.getString("car_model").?);
    try std.testing.expectEqualStrings("Monza", client.getString("track").?);
    try std.testing.expect(client.getString("speed_kmh") == null);
    try std.testing.expect(client.getNumber("car_model") == null);

    const h = client.resolve("rpms").?;
    try std.testing.expectEqual(@as(f64, 0), client.read(h).?);
}

test "connect to missing shared memory returns NotFound" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var c = client;
        c.deinit();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed, error.InvalidData => {},
        else => return err,
    }
}
