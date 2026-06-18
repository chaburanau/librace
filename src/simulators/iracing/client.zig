//! iRacing SDK client: shared-memory connection, variable lookup, and polling.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");
const session_mod = @import("session.zig");
const catalog_mod = @import("catalog.zig");
const keys = @import("keys.zig");
const testing = @import("testing.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    InvalidHeader,
    OutOfMemory,
};

/// Failure modes for type-coercing scalar reads.
pub const CoerceError = error{TypeMismatch};

/// Failure modes for reading a scalar telemetry variable by name.
pub const GetError = error{
    /// No variable with that name in the current catalog.
    NotFound,
    /// The variable exists but is an array — use `getRaw`.
    IsArray,
    /// The variable's type does not match the requested type.
    TypeMismatch,
};

/// Failure modes for reading via a cached [`VarHandle`].
pub const ReadError = error{
    /// The catalog was rebuilt since the handle was resolved — re-`resolve` it.
    Stale,
    /// The variable is an array — use `readRaw`.
    IsArray,
    /// The variable's type does not match the requested type.
    TypeMismatch,
};

/// Result of a single [`Client.poll`].
pub const PollStatus = enum {
    /// A fresh telemetry row was copied.
    ok,
    /// The simulator is not currently connected.
    disconnected,
    /// Connected, but no valid telemetry row could be read this tick.
    stale,
    /// The session changed and the catalog could not be rebuilt (e.g. allocation failure).
    rebuild_failed,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

pub const VarValue = union(enum) {
    int: i32,
    float: f32,
    double: f64,
    bool: bool,
    char: u8,
    bit_field: u32,

    /// Coerce a decoded scalar to `T`. Returns `error.TypeMismatch` when the tag does not match.
    pub fn coerce(self: VarValue, comptime T: type) CoerceError!T {
        return switch (T) {
            i32 => switch (self) {
                .int => |v| v,
                else => error.TypeMismatch,
            },
            u32 => switch (self) {
                .bit_field => |v| v,
                .int => |v| @intCast(v),
                else => error.TypeMismatch,
            },
            f32 => switch (self) {
                .float => |v| v,
                .double => |v| @floatCast(v),
                else => error.TypeMismatch,
            },
            f64 => switch (self) {
                .float => |v| @floatCast(v),
                .double => |v| v,
                else => error.TypeMismatch,
            },
            bool => switch (self) {
                .bool => |v| v,
                else => error.TypeMismatch,
            },
            u8 => switch (self) {
                .char => |v| v,
                else => error.TypeMismatch,
            },
            else => @compileError("unsupported coerce target type: " ++ @typeName(T)),
        };
    }

    /// Lenient numeric view of any scalar (int/bitfield/bool/char/float/double) as `f64`.
    pub fn toNumber(self: VarValue) f64 {
        return switch (self) {
            .int => |v| @floatFromInt(v),
            .bit_field => |v| @floatFromInt(v),
            .char => |v| @floatFromInt(v),
            .bool => |v| if (v) 1 else 0,
            .float => |v| v,
            .double => |v| v,
        };
    }
};

/// Raw bytes for a telemetry variable (including arrays). Valid until the next `poll`.
pub const VarRaw = struct {
    var_type: protocol.VarType,
    count: i32,
    data: []const u8,
};

/// Metadata for one entry in the per-session telemetry variable catalog.
pub const VarDescriptor = struct {
    name: []const u8,
    description: []const u8,
    unit: []const u8,
    var_type: protocol.VarType,
    count: i32,
    offset: i32,
};

/// Stable reference to a telemetry variable, resolved once and read many times.
///
/// A handle skips the per-read name lookup. It is invalidated when the session catalog is
/// rebuilt; reads then return `error.Stale` and the handle should be re-`resolve`d.
pub const VarHandle = struct {
    index: usize,
    version: u64,
    var_type: protocol.VarType,
    count: i32,
};

pub const VarNameIterator = catalog_mod.Catalog.NameIterator;
pub const SessionSectionIterator = session_mod.SectionIterator;

pub const Client = struct {
    mem: core.transport.mmap.SharedMemory,
    allocator: std.mem.Allocator,
    catalog: catalog_mod.Catalog,
    row_buffer: []u8,
    /// pyirsdk connection fallback: 0 = use status bit, 1 = probe SessionNum once, 2 = latched connected.
    connection_fallback_phase: u8 = 0,
    /// Optional handle to `Local\\IRSDKDataValidEvent`; null when unavailable.
    data_valid_event: ?core.transport.mmap.NamedEvent = null,
    /// Cache of session-info lookups, invalidated when `session_info_update` changes.
    session_cache: std.StringHashMapUnmanaged(?[]const u8) = .empty,
    session_cache_update: i32 = std.math.minInt(i32),

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.mem_map_name,
        });
        errdefer mem.close();

        const hdr = protocol.readHeader(mem.view) orelse return error.InvalidHeader;
        if (hdr.buf_len <= 0) return error.InvalidHeader;

        const row_buffer = try allocator.alloc(u8, @intCast(hdr.buf_len));
        errdefer allocator.free(row_buffer);

        var catalog = catalog_mod.Catalog.init(allocator);
        errdefer catalog.deinit();
        try catalog.rebuild(mem.view, hdr);

        var client = Client{
            .mem = mem,
            .allocator = allocator,
            .catalog = catalog,
            .row_buffer = row_buffer,
            .data_valid_event = core.transport.mmap.NamedEvent.open(protocol.data_valid_event_name) catch null,
        };
        _ = client.copyLatestRow();
        return client;
    }

    /// Retry `connect` until the simulator is available or `timeout_ms` elapses (`null` = forever).
    ///
    /// Useful when the consumer starts before the game. Polls roughly every 200 ms; only
    /// `error.NotFound` / `error.InvalidHeader` are retried, other errors propagate immediately.
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
                error.NotFound, error.InvalidHeader => {
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
        self.clearSessionCache();
        self.session_cache.deinit(self.allocator);
        if (self.data_valid_event) |*ev| ev.close();
        self.catalog.deinit();
        self.allocator.free(self.row_buffer);
        self.mem.close();
    }

    pub fn header(self: *const Client) ?*const protocol.Header {
        return protocol.readHeader(self.mem.view);
    }

    pub fn isConnected(self: *Client) bool {
        const hdr = self.header() orelse return false;
        if (hdr.isConnected()) {
            self.connection_fallback_phase = 0;
            return true;
        }
        // pyirsdk workaround: status bit clears briefly while vars remain valid.
        if (self.connection_fallback_phase == 0) self.connection_fallback_phase = 1;
        if (self.connection_fallback_phase == 1) {
            if (self.getRaw(keys.var_name.session_num)) |raw| {
                if (raw.count == 1) {
                    if (decodeScalar(raw.var_type, raw.data)) |v| {
                        if (v == .int and v.int != 0) self.connection_fallback_phase = 2;
                    }
                }
            }
        }
        return self.connection_fallback_phase == 2;
    }

    /// Copy the latest telemetry row from shared memory and refresh the catalog when the sim
    /// updates session info. The returned [`PollStatus`] distinguishes the failure modes.
    pub fn poll(self: *Client) PollStatus {
        if (!self.refreshCatalogIfNeeded()) return .rebuild_failed;
        if (!self.isConnected()) return .disconnected;
        if (!self.copyLatestRow()) return .stale;
        return .ok;
    }

    /// Block up to `timeout_ms` for the sim's data-valid event, then `poll`.
    ///
    /// Falls back to a plain `poll` when the event is unavailable.
    pub fn waitAndPoll(self: *Client, timeout_ms: u32) PollStatus {
        if (self.data_valid_event) |*ev| _ = ev.wait(timeout_ms);
        return self.poll();
    }

    /// Number of telemetry variables in the current session catalog.
    pub fn varCount(self: *const Client) usize {
        const hdr = self.header() orelse return 0;
        return @intCast(hdr.num_vars);
    }

    pub fn hasVar(self: *const Client, name: []const u8) bool {
        return self.catalog.get(name) != null;
    }

    /// Metadata for variable at `index` in the IRSDK catalog (0 .. `varCount()`).
    pub fn varDescriptor(self: *const Client, index: usize) ?VarDescriptor {
        const entry = self.catalog.entryAtIrSdkIndex(index) orelse return null;
        return descriptorFromEntry(entry);
    }

    pub fn varNameIterator(self: *const Client) VarNameIterator {
        return self.catalog.nameIterator();
    }

    /// Read a scalar telemetry variable by IRSDK name, distinguishing missing vs array.
    pub fn getValue(self: *const Client, name: []const u8) GetError!VarValue {
        const entry = self.catalog.get(name) orelse return error.NotFound;
        const raw = self.rawFromEntry(entry) orelse return error.NotFound;
        if (raw.count != 1) return error.IsArray;
        return decodeScalar(raw.var_type, raw.data) orelse error.IsArray;
    }

    /// Read a scalar telemetry variable by IRSDK name. Returns null for arrays or unknown names.
    pub fn get(self: *const Client, name: []const u8) ?VarValue {
        return self.getValue(name) catch null;
    }

    /// Read a scalar telemetry variable and coerce it to `T`.
    ///
    /// Returns `error.NotFound` when the name is missing, `error.IsArray` when it is an array,
    /// and `error.TypeMismatch` when the variable's type does not match `T`.
    pub fn getAs(self: *const Client, comptime T: type, name: []const u8) GetError!T {
        const value = try self.getValue(name);
        return value.coerce(T);
    }

    /// Read any scalar as `f64` (lenient numeric coercion). Null only when missing or an array.
    pub fn getNumber(self: *const Client, name: []const u8) ?f64 {
        const value = self.getValue(name) catch return null;
        return value.toNumber();
    }

    /// Read raw telemetry bytes by IRSDK name (scalars and arrays). Valid until next `poll`.
    pub fn getRaw(self: *const Client, name: []const u8) ?VarRaw {
        const entry = self.catalog.get(name) orelse return null;
        return self.rawFromEntry(entry);
    }

    /// Resolve a name into a [`VarHandle`] for repeated fast reads. Null when unknown.
    pub fn resolve(self: *const Client, name: []const u8) ?VarHandle {
        const index = self.catalog.getIndex(name) orelse return null;
        const entry = self.catalog.entryAt(index) orelse return null;
        return .{
            .index = index,
            .version = self.catalog.version,
            .var_type = entry.var_type,
            .count = entry.count,
        };
    }

    /// Read and coerce a scalar via a previously resolved handle.
    pub fn read(self: *const Client, comptime T: type, handle: VarHandle) ReadError!T {
        const value = try self.readScalar(handle);
        return value.coerce(T);
    }

    /// Read any scalar via a handle as `f64`. Null when the variable is an array.
    pub fn readNumber(self: *const Client, handle: VarHandle) error{Stale}!?f64 {
        if (handle.version != self.catalog.version) return error.Stale;
        const entry = self.catalog.entryAt(handle.index) orelse return error.Stale;
        const raw = self.rawFromEntry(entry) orelse return error.Stale;
        if (raw.count != 1) return null;
        const value = decodeScalar(raw.var_type, raw.data) orelse return null;
        return value.toNumber();
    }

    /// Read raw bytes via a handle (scalars and arrays). Valid until next `poll`.
    pub fn readRaw(self: *const Client, handle: VarHandle) error{Stale}!VarRaw {
        if (handle.version != self.catalog.version) return error.Stale;
        const entry = self.catalog.entryAt(handle.index) orelse return error.Stale;
        return self.rawFromEntry(entry) orelse error.Stale;
    }

    fn readScalar(self: *const Client, handle: VarHandle) ReadError!VarValue {
        if (handle.version != self.catalog.version) return error.Stale;
        const entry = self.catalog.entryAt(handle.index) orelse return error.Stale;
        const raw = self.rawFromEntry(entry) orelse return error.Stale;
        if (raw.count != 1) return error.IsArray;
        return decodeScalar(raw.var_type, raw.data) orelse error.IsArray;
    }

    /// Bind a caller-defined struct of named telemetry fields for ergonomic per-frame reads.
    ///
    /// `T`'s field names must match IRSDK variable names exactly (e.g. `Speed`, `Gear`, `RPM`),
    /// each field an integer, float, or bool with a default value. See [`Binding`].
    pub fn bind(self: *Client, comptime T: type) Binding(T) {
        return Binding(T).init(self);
    }

    /// Session-info YAML document (borrowed from shared memory; refreshed when the sim updates it).
    pub fn sessionYaml(self: *const Client) ?[]const u8 {
        const hdr = self.header() orelse return null;
        const yaml = hdr.sessionInfo(self.mem.view) orelse return null;
        return std.mem.trimEnd(u8, yaml, "\x00");
    }

    /// Read a session-info value by slash-separated path (`WeekendInfo/TrackName`).
    ///
    /// Results are cached until the session-info document changes. Paths are `Section/Key` or
    /// `Section/Nested/.../Key`; keys inside lists match the first occurrence (see `keys.session`).
    pub fn sessionGet(self: *Client, path: []const u8) ?[]const u8 {
        const hdr = self.header() orelse return null;
        self.syncSessionCache(hdr.session_info_update);
        if (self.session_cache.get(path)) |cached| return cached;

        const value = if (self.sessionYaml()) |yaml| session_mod.getByPath(yaml, path) else null;
        self.cacheSessionValue(path, value);
        return value;
    }

    /// Read a field from the *player's* `DriverInfo/Drivers` entry, resolved via `DriverCarIdx`.
    ///
    /// Pass a leaf key from `keys.driver` (e.g. `keys.driver.car_screen_name`). This is the
    /// correct way to get the player's car/name in multi-car sessions.
    pub fn playerDriverGet(self: *Client, leaf_key: []const u8) ?[]const u8 {
        const hdr = self.header() orelse return null;
        self.syncSessionCache(hdr.session_info_update);

        var key_buf: [96]u8 = undefined;
        const cache_key = std.fmt.bufPrint(&key_buf, "\x00drv/{s}", .{leaf_key}) catch
            return self.computePlayerDriverGet(leaf_key);
        if (self.session_cache.get(cache_key)) |cached| return cached;

        const value = self.computePlayerDriverGet(leaf_key);
        self.cacheSessionValue(cache_key, value);
        return value;
    }

    fn computePlayerDriverGet(self: *const Client, leaf_key: []const u8) ?[]const u8 {
        const yaml = self.sessionYaml() orelse return null;
        const idx = session_mod.getByPath(yaml, keys.session.driver_car_idx) orelse return null;
        const section = session_mod.extractSection(yaml, "DriverInfo") orelse return null;
        const item = session_mod.listItemMatching(section, "Drivers", keys.driver.car_idx, idx) orelse return null;
        return session_mod.extractKey(item, leaf_key);
    }

    /// Extract a top-level session-info section as raw YAML text.
    pub fn sessionSection(self: *const Client, section: []const u8) ?[]const u8 {
        const yaml = self.sessionYaml() orelse return null;
        return session_mod.extractSection(yaml, section);
    }

    pub fn sessionSectionIterator(self: *const Client) ?SessionSectionIterator {
        const yaml = self.sessionYaml() orelse return null;
        return session_mod.sectionIterator(yaml);
    }

    /// Monotonic counter; changes when session-info YAML is updated by the sim.
    pub fn sessionInfoUpdate(self: *const Client) ?i32 {
        const hdr = self.header() orelse return null;
        return hdr.session_info_update;
    }

    fn rawFromEntry(self: *const Client, entry: *const catalog_mod.VarEntry) ?VarRaw {
        const base: usize = @intCast(entry.offset);
        const elem_size = entry.var_type.byteSize();
        const total: usize = @as(usize, @intCast(entry.count)) * elem_size;
        if (base + total > self.row_buffer.len) return null;
        return .{
            .var_type = entry.var_type,
            .count = entry.count,
            .data = self.row_buffer[base..][0..total],
        };
    }

    fn syncSessionCache(self: *Client, update: i32) void {
        if (self.session_cache_update == update) return;
        self.clearSessionCache();
        self.session_cache_update = update;
    }

    fn cacheSessionValue(self: *Client, key: []const u8, value: ?[]const u8) void {
        const owned_key = self.allocator.dupe(u8, key) catch return;
        self.session_cache.put(self.allocator, owned_key, value) catch {
            self.allocator.free(owned_key);
        };
    }

    fn clearSessionCache(self: *Client) void {
        var it = self.session_cache.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.session_cache.clearRetainingCapacity();
    }

    fn refreshCatalogIfNeeded(self: *Client) bool {
        const hdr = self.header() orelse return false;
        if (!self.catalog.needsRebuild(hdr)) return true;

        self.catalog.rebuild(self.mem.view, hdr) catch return false;

        const buf_len: usize = @intCast(hdr.buf_len);
        if (buf_len != self.row_buffer.len) {
            const new_buffer = self.allocator.alloc(u8, buf_len) catch return false;
            self.allocator.free(self.row_buffer);
            self.row_buffer = new_buffer;
        }
        return true;
    }

    fn copyLatestRow(self: *Client) bool {
        const hdr = self.header() orelse return false;
        return protocol.copyLatestRow(self.mem.view, hdr, self.row_buffer);
    }
};

fn descriptorFromEntry(entry: *const catalog_mod.VarEntry) VarDescriptor {
    return .{
        .name = entry.name,
        .description = entry.description,
        .unit = entry.unit,
        .var_type = entry.var_type,
        .count = entry.count,
        .offset = entry.offset,
    };
}

/// A live, typed view over a fixed set of telemetry variables.
///
/// Built via [`Client.bind`]. Each `update` resolves any missing/stale handles, then fills
/// `values`. Fields that are missing this frame keep their previous value; query `isPresent`
/// to tell whether a field was populated.
pub fn Binding(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Binding requires a struct type, got " ++ @typeName(T));
    const fields = info.@"struct".fields;

    inline for (fields) |f| {
        if (!isNumericField(f.type)) {
            @compileError("Binding field '" ++ f.name ++ "' must be an integer, float, or bool");
        }
    }

    return struct {
        const Self = @This();

        client: *Client,
        values: T,
        handles: [fields.len]?VarHandle,
        present: [fields.len]bool,

        pub fn init(client: *Client) Self {
            return .{
                .client = client,
                .values = .{},
                .handles = [_]?VarHandle{null} ** fields.len,
                .present = [_]bool{false} ** fields.len,
            };
        }

        /// Refresh every bound field from the latest polled row.
        pub fn update(self: *Self) void {
            inline for (fields, 0..) |f, i| {
                self.present[i] = self.updateField(f.name, f.type, i);
            }
        }

        fn updateField(self: *Self, comptime name: []const u8, comptime FieldType: type, comptime i: usize) bool {
            const handle = self.resolveHandle(name, i) orelse return false;
            const num = self.client.readNumber(handle) catch {
                self.handles[i] = null;
                return false;
            };
            const n = num orelse return false;
            @field(self.values, name) = castNumber(FieldType, n);
            return true;
        }

        fn resolveHandle(self: *Self, comptime name: []const u8, comptime i: usize) ?VarHandle {
            if (self.handles[i]) |h| {
                if (h.version == self.client.catalog.version) return h;
            }
            const resolved = self.client.resolve(name);
            self.handles[i] = resolved;
            return resolved;
        }

        /// Whether `field_name` was populated by the most recent `update`.
        pub fn isPresent(self: *const Self, comptime field_name: []const u8) bool {
            inline for (fields, 0..) |f, i| {
                if (comptime std.mem.eql(u8, f.name, field_name)) return self.present[i];
            }
            @compileError("unknown binding field: " ++ field_name);
        }
    };
}

fn isNumericField(comptime FieldType: type) bool {
    return switch (@typeInfo(FieldType)) {
        .int, .float, .bool => true,
        else => false,
    };
}

fn castNumber(comptime FieldType: type, n: f64) FieldType {
    return switch (@typeInfo(FieldType)) {
        .float => @floatCast(n),
        .int => @intFromFloat(@round(n)),
        .bool => n != 0,
        else => @compileError("unsupported binding field type: " ++ @typeName(FieldType)),
    };
}

pub fn decodeScalar(var_type: protocol.VarType, data: []const u8) ?VarValue {
    const elem_size = var_type.byteSize();
    if (data.len < elem_size) return null;
    return switch (var_type) {
        .char => .{ .char = data[0] },
        .bool => .{ .bool = data[0] != 0 },
        .int => .{ .int = std.mem.readInt(i32, data[0..4], .little) },
        .bit_field => .{ .bit_field = std.mem.readInt(u32, data[0..4], .little) },
        .float => .{ .float = @bitCast(std.mem.readInt(u32, data[0..4], .little)) },
        .double => .{ .double = @bitCast(std.mem.readInt(u64, data[0..8], .little)) },
    };
}

test "decode scalar int" {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, 3, .little);
    const v = decodeScalar(.int, &buf).?;
    try std.testing.expect(v == .int);
    try std.testing.expectEqual(@as(i32, 3), v.int);
}

test "decode scalar float" {
    var buf: [4]u8 = undefined;
    const f: f32 = 42.5;
    std.mem.writeInt(u32, &buf, @bitCast(f), .little);
    const v = decodeScalar(.float, &buf).?;
    try std.testing.expect(v == .float);
    try std.testing.expectApproxEqAbs(42.5, v.float, 0.001);
}

test "VarValue coerce, toNumber" {
    try std.testing.expectEqual(@as(i32, 3), (VarValue{ .int = 3 }).coerce(i32));
    try std.testing.expectEqual(@as(f32, 1.5), (VarValue{ .float = 1.5 }).coerce(f32));
    try std.testing.expectEqual(@as(f64, 2.5), (VarValue{ .double = 2.5 }).coerce(f64));
    try std.testing.expect((VarValue{ .float = 1.0 }).coerce(i32) == error.TypeMismatch);
    try std.testing.expectEqual(@as(f64, 7), (VarValue{ .int = 7 }).toNumber());
    try std.testing.expectEqual(@as(f64, 1), (VarValue{ .bool = true }).toNumber());
}

/// Build a single-variable fixture client over `mem`/`row_buffer` for tests.
fn fixtureClient(
    mem: []u8,
    row_buffer: []u8,
    var_type: protocol.VarType,
    count: i32,
    name: []const u8,
) !Client {
    @memset(mem, 0);
    const hdr: *protocol.Header = @ptrCast(@alignCast(mem.ptr));
    hdr.* = testing.initHeader(.{
        .session_info_update = 1,
        .num_vars = 1,
        .buf_len = @intCast(row_buffer.len),
        .var_buf = .{
            .{ .tick_count = 1, .buf_offset = 200, .tick_count_begin = 1, ._pad = 0 },
            std.mem.zeroes(protocol.VarBuf),
            std.mem.zeroes(protocol.VarBuf),
            std.mem.zeroes(protocol.VarBuf),
        },
    });
    const vh: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    vh.* = testing.initVarHeader(.{
        .type = @intFromEnum(var_type),
        .count = count,
        .name = name,
        .offset = 0,
    });
    var client = Client{
        .mem = .{},
        .allocator = std.testing.allocator,
        .catalog = catalog_mod.Catalog.init(std.testing.allocator),
        .row_buffer = row_buffer,
    };
    try client.catalog.rebuild(mem, hdr);
    return client;
}

test "getAs, getValue, getNumber distinguish missing, array, mismatch" {
    var mem: [512]u8 = undefined;
    var row_buffer: [4]u8 = undefined;
    std.mem.writeInt(i32, &row_buffer, 4, .little);
    var client = try fixtureClient(&mem, &row_buffer, .int, 1, "Gear");
    defer client.catalog.deinit();

    try std.testing.expectEqual(@as(i32, 4), try client.getAs(i32, "Gear"));
    try std.testing.expectEqual(@as(f64, 4), client.getNumber("Gear").?);
    try std.testing.expect(client.getAs(bool, "Gear") == error.TypeMismatch);
    try std.testing.expect(client.getAs(i32, "Missing") == error.NotFound);
    try std.testing.expect(client.getValue("Missing") == error.NotFound);
    try std.testing.expect(client.getNumber("Missing") == null);
}

test "getValue reports IsArray for non-scalar variables" {
    var mem: [512]u8 = undefined;
    var row_buffer: [8]u8 = undefined;
    @memset(&row_buffer, 0);
    var client = try fixtureClient(&mem, &row_buffer, .int, 2, "Wide");
    defer client.catalog.deinit();

    try std.testing.expect(client.getValue("Wide") == error.IsArray);
    try std.testing.expect(client.getAs(i32, "Wide") == error.IsArray);
    try std.testing.expect(client.getNumber("Wide") == null);
    try std.testing.expect(client.get("Wide") == null);
}

test "handle reads and detect staleness on catalog rebuild" {
    var mem: [512]u8 = undefined;
    var row_buffer: [4]u8 = undefined;
    std.mem.writeInt(i32, &row_buffer, 5, .little);
    var client = try fixtureClient(&mem, &row_buffer, .int, 1, "Gear");
    defer client.catalog.deinit();

    const handle = client.resolve("Gear").?;
    try std.testing.expectEqual(@as(i32, 5), try client.read(i32, handle));
    try std.testing.expectEqual(@as(f64, 5), (try client.readNumber(handle)).?);

    // Rebuild the catalog (new session) — the old handle must now be stale.
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.session_info_update = 2;
    try client.catalog.rebuild(&mem, hdr);
    try std.testing.expect(client.read(i32, handle) == error.Stale);
}

test "comptime struct binding fills typed fields" {
    var mem: [512]u8 = undefined;
    var row_buffer: [4]u8 = undefined;
    std.mem.writeInt(i32, &row_buffer, 3, .little);
    var client = try fixtureClient(&mem, &row_buffer, .int, 1, "Gear");
    defer client.catalog.deinit();

    const Telemetry = struct {
        Gear: i32 = -99,
        Missing: f32 = 1.25,
    };
    var bound = client.bind(Telemetry);
    bound.update();

    try std.testing.expectEqual(@as(i32, 3), bound.values.Gear);
    try std.testing.expect(bound.isPresent("Gear"));
    try std.testing.expect(!bound.isPresent("Missing"));
    try std.testing.expectEqual(@as(f32, 1.25), bound.values.Missing);
}

test "getRaw returns null when variable extends past row buffer" {
    var mem: [512]u8 = undefined;
    var row_buffer: [8]u8 = undefined;
    @memset(&row_buffer, 0);
    var client = try fixtureClient(&mem, &row_buffer, .double, 2, "Wide");
    defer client.catalog.deinit();

    try std.testing.expect(client.getRaw("Wide") == null);
}

test "connect and deinit release resources" {
    const allocator = std.testing.allocator;
    var client = Client.connect(allocator) catch |err| switch (err) {
        error.NotFound, error.MapFailed, error.InvalidHeader => return error.SkipZigTest,
        else => return err,
    };
    client.deinit();
}

test "connect to missing shared memory returns NotFound" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const result = core.transport.mmap.SharedMemory.open(.{
        .name = "Local\\librace_a8f3c912_connect_test_missing",
    });
    if (result) |opened| {
        var mem = opened;
        defer mem.close();
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.NotFound => {},
        error.MapFailed => return error.SkipZigTest,
        else => return err,
    }
}
