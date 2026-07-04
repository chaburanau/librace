//! Le Mans Ultimate client for the native `LMU_Data` shared-memory interface.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    InvalidData,
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

const SnapshotResult = enum { ok, disconnected, stale };

pub const Client = struct {
    allocator: std.mem.Allocator,
    mem: core.transport.mmap.SharedMemory,
    lock: ?SharedMemoryLock = null,
    data_event: ?core.transport.mmap.NamedEvent = null,

    telem: *protocol.TelemInfoV01,
    session_info: *protocol.ScoringInfoV01,
    vehicle_info: *protocol.VehicleScoringInfoV01,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.mem_map_name,
            .size = @sizeOf(protocol.SharedMemoryObjectOut),
        });
        errdefer mem.close();
        if (mem.view.len < @sizeOf(protocol.SharedMemoryObjectOut)) return error.InvalidData;

        var lock: ?SharedMemoryLock = SharedMemoryLock.open() catch null;
        errdefer if (lock) |*l| l.close();

        var data_event = core.transport.mmap.NamedEvent.open(.{ .name = protocol.data_event_name }) catch null;
        errdefer if (data_event) |*ev| ev.close();

        const telem = try allocator.create(protocol.TelemInfoV01);
        errdefer allocator.destroy(telem);
        const session_info = try allocator.create(protocol.ScoringInfoV01);
        errdefer allocator.destroy(session_info);
        const vehicle_info = try allocator.create(protocol.VehicleScoringInfoV01);
        errdefer allocator.destroy(vehicle_info);

        telem.* = .{};
        session_info.* = .{};
        vehicle_info.* = .{};

        var client = Client{
            .allocator = allocator,
            .mem = mem,
            .lock = lock,
            .data_event = data_event,
            .telem = telem,
            .session_info = session_info,
            .vehicle_info = vehicle_info,
        };
        _ = client.copySnapshot();
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.telem);
        self.allocator.destroy(self.session_info);
        self.allocator.destroy(self.vehicle_info);
        if (self.data_event) |*ev| ev.close();
        if (self.lock) |*l| l.close();
        self.mem.close();
    }

    pub fn isConnected(self: *const Client) bool {
        const active = protocol.readActiveVehicles(self.mem.view) orelse 0;
        if (active > 0 and (protocol.readPlayerHasVehicle(self.mem.view) orelse false)) return true;
        return self.session_info.in_realtime or self.telem.elapsed_time > 0;
    }

    pub fn poll(self: *Client) PollStatus {
        return switch (self.copySnapshot()) {
            .ok => .ok,
            .disconnected => .disconnected,
            .stale => .stale,
        };
    }

    pub fn waitAndPoll(self: *Client, timeout: std.Io.Duration) PollStatus {
        if (self.data_event) |*ev| _ = ev.wait(timeout);
        return self.poll();
    }

    pub fn telemetry(self: *const Client) *const protocol.TelemInfoV01 {
        return self.telem;
    }

    pub fn session(self: *const Client) *const protocol.ScoringInfoV01 {
        return self.session_info;
    }

    pub fn vehicle(self: *const Client) *const protocol.VehicleScoringInfoV01 {
        return self.vehicle_info;
    }

    fn copySnapshot(self: *Client) SnapshotResult {
        var locked = false;
        if (self.lock) |*l| {
            locked = l.tryLock();
        }
        defer if (locked) {
            if (self.lock) |*l| l.unlock();
        };

        return self.copySnapshotUnlocked();
    }

    fn copySnapshotUnlocked(self: *Client) SnapshotResult {
        if (self.mem.view.len < @sizeOf(protocol.SharedMemoryObjectOut)) return .stale;

        const active = protocol.readActiveVehicles(self.mem.view) orelse return .stale;
        const idx = protocol.readPlayerVehicleIdx(self.mem.view) orelse return .stale;
        const has_vehicle = protocol.readPlayerHasVehicle(self.mem.view) orelse false;
        if (!has_vehicle or active == 0 or idx >= active or idx >= protocol.max_vehicles) return .disconnected;

        if (!copyAt(protocol.ScoringInfoV01, self.mem.view, protocol.scoring_info_offset, self.session_info)) return .stale;

        const telem_offset = protocol.telemetry_info_offset + @as(usize, idx) * @sizeOf(protocol.TelemInfoV01);
        if (!copyAt(protocol.TelemInfoV01, self.mem.view, telem_offset, self.telem)) return .stale;

        const vehicle_index = self.findPlayerScoringIndex(idx);
        const vehicle_offset = protocol.vehicle_scoring_offset + vehicle_index * @sizeOf(protocol.VehicleScoringInfoV01);
        if (!copyAt(protocol.VehicleScoringInfoV01, self.mem.view, vehicle_offset, self.vehicle_info)) return .stale;

        return .ok;
    }

    fn findPlayerScoringIndex(self: *const Client, player_telem_index: usize) usize {
        const num_vehicles = @min(
            @as(usize, @intCast(@max(self.session_info.num_vehicles, 0))),
            protocol.max_vehicles,
        );
        var fallback: usize = @min(player_telem_index, if (num_vehicles == 0) 0 else num_vehicles - 1);
        var i: usize = 0;
        while (i < num_vehicles) : (i += 1) {
            const offset = protocol.vehicle_scoring_offset + i * @sizeOf(protocol.VehicleScoringInfoV01);
            if (offset + @sizeOf(protocol.VehicleScoringInfoV01) > self.mem.view.len) break;
            const bytes = self.mem.view[offset..][0..@sizeOf(protocol.VehicleScoringInfoV01)];
            const is_player = bytes[@offsetOf(protocol.VehicleScoringInfoV01, "is_player")] != 0;
            if (is_player) return i;
            const id_offset = @offsetOf(protocol.VehicleScoringInfoV01, "id");
            const id = std.mem.readInt(i32, bytes[id_offset..][0..4], .little);
            if (id == self.telem.id) fallback = i;
        }
        return fallback;
    }
};

fn copyAt(comptime T: type, view: []const u8, offset: usize, dest: *T) bool {
    const size = @sizeOf(T);
    if (offset + size > view.len) return false;
    @memcpy(std.mem.asBytes(dest), view[offset..][0..size]);
    return true;
}

const SharedMemoryLock = struct {
    mem: core.transport.mmap.SharedMemory,
    event: ?core.transport.mmap.NamedEvent = null,

    const size = 8;
    const waiters_offset = 0;
    const busy_offset = 4;

    fn open() core.transport.mmap.SharedMemory.OpenError!SharedMemoryLock {
        var mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.lock_map_name,
            .size = size,
            .access = .read_write,
        });
        errdefer mem.close();
        if (mem.view.len < size) return error.MapFailed;

        const event = core.transport.mmap.NamedEvent.open(.{
            .name = protocol.lock_event_name,
            .access = .signal,
        }) catch null;
        return .{ .mem = mem, .event = event };
    }

    fn close(self: *SharedMemoryLock) void {
        if (self.event) |*ev| ev.close();
        self.mem.close();
    }

    fn tryLock(self: *SharedMemoryLock) bool {
        var spins: u32 = 0;
        while (spins < 4000) : (spins += 1) {
            if (@cmpxchgStrong(i32, self.i32Ptr(busy_offset), 0, 1, .acquire, .monotonic) == null) {
                return true;
            }
            std.atomic.spinLoopHint();
        }
        return false;
    }

    fn unlock(self: *SharedMemoryLock) void {
        @atomicStore(i32, self.i32Ptr(busy_offset), 0, .release);
        if (@atomicLoad(i32, self.i32Ptr(waiters_offset), .acquire) > 0) {
            if (self.event) |*ev| _ = ev.set();
        }
    }

    fn i32Ptr(self: *SharedMemoryLock, offset: usize) *i32 {
        return @ptrCast(@alignCast(&self.mem.view[offset]));
    }
};

test "typed snapshot access and string decode" {
    const allocator = std.testing.allocator;
    const telem = try allocator.create(protocol.TelemInfoV01);
    defer allocator.destroy(telem);
    const session = try allocator.create(protocol.ScoringInfoV01);
    defer allocator.destroy(session);
    const vehicle = try allocator.create(protocol.VehicleScoringInfoV01);
    defer allocator.destroy(vehicle);

    telem.* = .{};
    session.* = .{};
    vehicle.* = .{};
    telem.engine_rpm = 8025.0;
    telem.gear = 5;
    @memcpy(telem.vehicle_name[0.."Ferrari 499P".len], "Ferrari 499P");
    @memcpy(session.track_name[0.."Le Mans".len], "Le Mans");
    vehicle.best_lap_time = 210.5;

    var client = Client{
        .allocator = allocator,
        .mem = .{},
        .telem = telem,
        .session_info = session,
        .vehicle_info = vehicle,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 8025.0), client.telemetry().engine_rpm, 0.001);
    try std.testing.expectEqual(@as(i32, 5), client.telemetry().gear);
    try std.testing.expectApproxEqAbs(@as(f64, 210.5), client.vehicle().best_lap_time, 0.001);

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ferrari 499P", client.telemetry().vehicleNameUtf8(&out).?);
    try std.testing.expectEqualStrings("Le Mans", client.session().trackNameUtf8(&out).?);
}

test "connect handles available or missing LMU shared memory" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var c = client;
        c.deinit();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed, error.InvalidData => {},
        else => return err,
    }
}
