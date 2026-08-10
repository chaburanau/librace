//! Lean iRacing SDK client with lazy session and variable metadata parsing.

const std = @import("std");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");
const session_mod = @import("session.zig");
const testing = @import("testing.zig");
const readSharedI32 = protocol.readSharedI32;

pub const SessionSnapshot = session_mod.Snapshot;
pub const SessionParseError = session_mod.ParseError;
pub const VariableType = protocol.VarType;

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    InvalidHeader,
    OutOfMemory,
};

pub const PollStatus = enum {
    updated,
    unchanged,
    disconnected,
    stale,
    rebuild_failed,

    pub fn isOk(self: PollStatus) bool {
        return self == .updated or self == .unchanged;
    }
};

pub const HeaderStatus = struct {
    raw: i32,

    pub fn isConnected(self: HeaderStatus) bool {
        return self.raw & protocol.status_connected != 0;
    }
};

pub const VariableDescriptor = struct {
    native_index: usize,
    var_type: VariableType,
    offset: usize,
    count: usize,
    count_as_time: bool,
    name_buffer: [protocol.max_string]u8,
    name_len: u8,
    description_buffer: [protocol.max_desc]u8,
    description_len: u8,
    unit_buffer: [protocol.max_string]u8,
    unit_len: u8,

    pub fn name(self: *const VariableDescriptor) []const u8 {
        return self.name_buffer[0..self.name_len];
    }

    pub fn description(self: *const VariableDescriptor) []const u8 {
        return self.description_buffer[0..self.description_len];
    }

    pub fn unit(self: *const VariableDescriptor) []const u8 {
        return self.unit_buffer[0..self.unit_len];
    }
};

/// Allocation-free metadata cached by the caller for repeated row reads.
pub const Variable = struct {
    native_index: usize,
    catalog_generation: u64,
    var_type: VariableType,
    count: usize,
    start: usize,
    end: usize,
};

pub const VariableArrayView = struct {
    var_type: VariableType,
    count: usize,
    bytes: []const u8,

    pub fn value(self: VariableArrayView, index: usize) ?VariableValue {
        if (index >= self.count) return null;
        const size = variableByteSize(self.var_type) orelse return null;
        const start = std.math.mul(usize, index, size) catch return null;
        return decodeScalar(self.var_type, self.bytes[start..][0..size]);
    }
};

pub const VariableValue = union(enum) {
    int: i32,
    float: f32,
    double: f64,
    bool: bool,
    char: u8,
    bit_field: u32,
    array: VariableArrayView,

    pub fn asInt(self: VariableValue) ?i32 {
        return switch (self) {
            .int => |value| value,
            else => null,
        };
    }

    pub fn asFloat(self: VariableValue) ?f64 {
        return switch (self) {
            .float => |value| value,
            .double => |value| value,
            else => null,
        };
    }

    pub fn asBool(self: VariableValue) ?bool {
        return switch (self) {
            .bool => |value| value,
            else => null,
        };
    }
};

pub const VariableError = error{
    IndexOutOfBounds,
    NotFound,
    InvalidData,
    Stale,
    LayoutChanged,
};

const Catalog = struct {
    num_vars: i32,
    var_header_offset: i32,
    buf_len: i32,

    fn eql(a: Catalog, b: Catalog) bool {
        return a.num_vars == b.num_vars and
            a.var_header_offset == b.var_header_offset and
            a.buf_len == b.buf_len;
    }
};

pub const Client = struct {
    mem: core.transport.mmap.SharedMemory,
    allocator: std.mem.Allocator,
    row_buffer: []u8,
    scratch_buffer: []u8,
    catalog: Catalog,
    catalog_generation: u64 = 1,
    last_tick: ?i32 = null,
    connected: bool = false,
    data_valid_event: ?core.transport.mmap.NamedEvent = null,
    data_valid_event_attempted: bool = false,
    io: ?std.Io = null,
    stale_timeout: ?std.Io.Duration = null,
    stale_deadline: ?std.Io.Clock.Timestamp = null,
    owns_buffers: bool = true,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var mem = try core.transport.mmap.SharedMemory.open(.{ .name = protocol.mem_map_name });
        errdefer mem.close();

        const hdr = protocol.readHeader(mem.view) orelse return error.InvalidHeader;
        const catalog = readCatalog(hdr) orelse return error.InvalidHeader;
        const row_buffer = try allocator.alloc(u8, @intCast(catalog.buf_len));
        errdefer allocator.free(row_buffer);
        const scratch_buffer = try allocator.alloc(u8, @intCast(catalog.buf_len));
        errdefer allocator.free(scratch_buffer);

        var client = Client{
            .mem = mem,
            .allocator = allocator,
            .row_buffer = row_buffer,
            .scratch_buffer = scratch_buffer,
            .catalog = catalog,
        };
        const source = protocol.latestRowSource(client.mem.view, hdr);
        const copied = if (source) |row|
            protocol.copyRow(client.mem.view, hdr, row, client.row_buffer)
        else
            false;
        if (copied) client.last_tick = source.?.tick_count;
        client.connected = copied and hdr.isConnected();
        return client;
    }

    pub fn deinit(self: *Client) void {
        if (self.data_valid_event) |*event| event.close();
        if (self.owns_buffers) {
            self.allocator.free(self.row_buffer);
            self.allocator.free(self.scratch_buffer);
        }
        self.mem.close();
        self.* = undefined;
    }

    pub fn isConnected(self: *const Client) bool {
        return self.connected;
    }

    pub fn configureLiveness(
        self: *Client,
        io: std.Io,
        stale_timeout: ?std.Io.Duration,
    ) void {
        self.io = io;
        self.stale_timeout = stale_timeout;
        self.refreshStaleDeadline();
    }

    pub fn header(self: *const Client) HeaderView {
        return .{ .client = self };
    }

    pub fn session(self: *const Client) SessionView {
        return .{ .client = self };
    }

    pub fn variables(self: *Client) VariablesView {
        return .{ .client = self };
    }

    pub fn poll(self: *Client) PollStatus {
        const was_connected = self.connected;
        const hdr = protocol.readHeader(self.mem.view) orelse {
            self.connected = false;
            return .rebuild_failed;
        };
        if (!hdr.isConnected()) {
            self.connected = false;
            return .disconnected;
        }
        self.connected = true;

        const current_catalog = readCatalog(hdr) orelse return .rebuild_failed;

        const source = protocol.latestRowSource(self.mem.view, hdr) orelse return .stale;
        const catalog_changed = !Catalog.eql(current_catalog, self.catalog);
        const resized = current_catalog.buf_len != self.catalog.buf_len;
        const tick_changed = self.last_tick == null or source.tick_count != self.last_tick.?;
        const tick_rolled_back = if (self.last_tick) |last| source.tick_count < last else false;
        const reconnected = !was_connected;

        // A stable tick and stable catalog need no row copy.
        if (!catalog_changed and !tick_changed and !reconnected) {
            if (self.staleDeadlineReached()) {
                self.connected = false;
                return .stale;
            }
            return .unchanged;
        }

        if (resized) {
            const replacement_row = self.allocator.alloc(u8, @intCast(current_catalog.buf_len)) catch
                return .rebuild_failed;
            const replacement_scratch = self.allocator.alloc(u8, @intCast(current_catalog.buf_len)) catch {
                self.allocator.free(replacement_row);
                return .rebuild_failed;
            };
            if (!protocol.copyRow(self.mem.view, hdr, source, replacement_row)) {
                self.allocator.free(replacement_row);
                self.allocator.free(replacement_scratch);
                return .stale;
            }
            const after = readCatalog(hdr) orelse {
                self.allocator.free(replacement_row);
                self.allocator.free(replacement_scratch);
                return .rebuild_failed;
            };
            if (!Catalog.eql(after, current_catalog)) {
                self.allocator.free(replacement_row);
                self.allocator.free(replacement_scratch);
                return .stale;
            }
            if (!hdr.isConnected()) {
                self.allocator.free(replacement_row);
                self.allocator.free(replacement_scratch);
                self.connected = false;
                return .disconnected;
            }
            if (self.owns_buffers) {
                self.allocator.free(self.row_buffer);
                self.allocator.free(self.scratch_buffer);
            }
            self.row_buffer = replacement_row;
            self.scratch_buffer = replacement_scratch;
            self.owns_buffers = true;
            self.catalog = current_catalog;
            self.catalog_generation +%= 1;
            self.last_tick = source.tick_count;
            self.refreshStaleDeadline();
            return .updated;
        }

        if (!protocol.copyRow(self.mem.view, hdr, source, self.scratch_buffer)) return .stale;
        const after = readCatalog(hdr) orelse return .rebuild_failed;
        if (!Catalog.eql(after, current_catalog)) return .stale;
        if (!hdr.isConnected()) {
            self.connected = false;
            return .disconnected;
        }
        std.mem.swap([]u8, &self.row_buffer, &self.scratch_buffer);
        if (catalog_changed) {
            self.catalog = current_catalog;
        }
        if (catalog_changed or tick_rolled_back or reconnected) self.catalog_generation +%= 1;
        self.last_tick = source.tick_count;
        self.refreshStaleDeadline();
        return .updated;
    }

    pub fn waitAndPoll(self: *Client, timeout: std.Io.Duration) PollStatus {
        const before_wait = self.poll();
        if (before_wait != .unchanged) return before_wait;

        if (!self.data_valid_event_attempted) {
            self.data_valid_event_attempted = true;
            self.data_valid_event = core.transport.mmap.NamedEvent.open(.{
                .name = protocol.data_valid_event_name,
            }) catch null;
        }
        if (self.data_valid_event) |*event| {
            _ = event.wait(timeout);
        } else if (self.io) |io| {
            std.Io.sleep(io, timeout, .awake) catch {};
        }
        return self.poll();
    }

    fn refreshStaleDeadline(self: *Client) void {
        const io = self.io orelse return;
        const timeout = self.stale_timeout orelse {
            self.stale_deadline = null;
            return;
        };
        if (timeout.nanoseconds < 0) {
            self.stale_deadline = null;
            return;
        }
        self.stale_deadline = std.Io.Clock.Timestamp.fromNow(io, .{
            .raw = timeout,
            .clock = .awake,
        });
    }

    fn staleDeadlineReached(self: *const Client) bool {
        const io = self.io orelse return false;
        const deadline = self.stale_deadline orelse return false;
        return deadline.durationFromNow(io).raw.nanoseconds <= 0;
    }
};

pub const HeaderView = struct {
    client: *const Client,

    pub fn version(self: HeaderView) ?i32 {
        const hdr = self.raw() orelse return null;
        return readSharedI32(&hdr.ver);
    }

    pub fn status(self: HeaderView) ?HeaderStatus {
        const hdr = self.raw() orelse return null;
        return .{ .raw = readSharedI32(&hdr.status) };
    }

    pub fn tickRate(self: HeaderView) ?i32 {
        const hdr = self.raw() orelse return null;
        return readSharedI32(&hdr.tick_rate);
    }

    pub fn tickCount(self: HeaderView) ?i32 {
        const hdr = self.raw() orelse return null;
        const buf = protocol.latestVarBuf(hdr) orelse return null;
        return readSharedI32(&buf.tick_count);
    }

    pub fn variablesLen(self: HeaderView) usize {
        const hdr = self.raw() orelse return 0;
        const count = readSharedI32(&hdr.num_vars);
        return if (count < 0) 0 else @intCast(count);
    }

    pub fn isConnected(self: HeaderView) bool {
        return if (self.status()) |value| value.isConnected() else false;
    }

    fn raw(self: HeaderView) ?*const protocol.Header {
        return protocol.readHeader(self.client.mem.view);
    }
};

pub const SessionView = struct {
    client: *const Client,

    pub fn version(self: SessionView) ?i32 {
        const hdr = protocol.readHeader(self.client.mem.view) orelse return null;
        return readSharedI32(&hdr.session_info_update);
    }

    pub fn snapshot(self: SessionView) !session_mod.Snapshot {
        const hdr = protocol.readHeader(self.client.mem.view) orelse return error.InvalidHeader;
        const version_before = readSharedI32(&hdr.session_info_update);
        const raw = hdr.sessionInfo(self.client.mem.view) orelse return error.NoSessionInfo;
        const yaml = std.mem.trimEnd(u8, raw, "\x00");
        var result = try session_mod.parse(self.client.allocator, yaml, version_before);
        errdefer result.deinit();
        if (readSharedI32(&hdr.session_info_update) != version_before) return error.LayoutChanged;
        return result;
    }
};

pub const VariablesView = struct {
    client: *Client,

    pub fn version(self: VariablesView) u64 {
        return self.client.catalog_generation;
    }

    /// Resolve a native descriptor by name without allocating. Cache the returned
    /// handle and pass it to `value` on every telemetry update.
    pub fn find(self: VariablesView, name: []const u8) VariableError!?Variable {
        const hdr = protocol.readHeader(self.client.mem.view) orelse return error.InvalidData;
        const before = readCatalog(hdr) orelse return error.InvalidData;
        if (!Catalog.eql(before, self.client.catalog)) return error.Stale;
        const count: usize = @intCast(before.num_vars);
        for (0..count) |index| {
            const raw = protocol.readVarHeader(self.client.mem.view, hdr, index) orelse
                return error.InvalidData;
            if (std.mem.eql(u8, raw.nameSlice(), name)) {
                const variable = parseVariable(raw, index, @intCast(before.buf_len), self.version()) orelse
                    return error.InvalidData;
                const after = readCatalog(hdr) orelse return error.LayoutChanged;
                if (!Catalog.eql(before, after)) return error.LayoutChanged;
                return variable;
            }
        }
        const after = readCatalog(hdr) orelse return error.LayoutChanged;
        if (!Catalog.eql(before, after)) return error.LayoutChanged;
        return null;
    }

    /// Resolve one native IRSDK variable index without allocating.
    pub fn at(self: VariablesView, native_index: usize) VariableError!Variable {
        if (native_index >= @as(usize, @intCast(self.client.catalog.num_vars)))
            return error.IndexOutOfBounds;
        const hdr = protocol.readHeader(self.client.mem.view) orelse return error.InvalidData;
        const before = readCatalog(hdr) orelse return error.InvalidData;
        if (!Catalog.eql(before, self.client.catalog)) return error.Stale;
        const raw = protocol.readVarHeader(self.client.mem.view, hdr, native_index) orelse
            return error.InvalidData;
        const variable = parseVariable(raw, native_index, @intCast(before.buf_len), self.version()) orelse
            return error.InvalidData;
        const after = readCatalog(hdr) orelse return error.LayoutChanged;
        if (!Catalog.eql(before, after)) return error.LayoutChanged;
        return variable;
    }

    pub fn descriptors(self: VariablesView) VariableError!DescriptorIterator {
        const hdr = protocol.readHeader(self.client.mem.view) orelse return error.InvalidData;
        const catalog = readCatalog(hdr) orelse return error.InvalidData;
        if (!Catalog.eql(catalog, self.client.catalog)) return error.Stale;
        return .{
            .view = self,
            .catalog_generation = self.version(),
            .count = @intCast(catalog.num_vars),
        };
    }

    /// Read a caller-cached handle from the most recently polled owned row.
    ///
    /// Array bytes are borrowed and remain valid until the next successful `poll` or `deinit`.
    pub fn value(self: VariablesView, variable: Variable) VariableError!VariableValue {
        if (variable.catalog_generation != self.client.catalog_generation) return error.Stale;
        if (variable.native_index >= @as(usize, @intCast(self.client.catalog.num_vars)) or
            variable.end > self.client.row_buffer.len or variable.start > variable.end)
        {
            return error.InvalidData;
        }
        const bytes = self.client.row_buffer[variable.start..variable.end];
        if (variable.count == 1)
            return decodeScalar(variable.var_type, bytes) orelse error.InvalidData;
        return .{ .array = .{
            .var_type = variable.var_type,
            .count = variable.count,
            .bytes = bytes,
        } };
    }
};

pub const DescriptorIterator = struct {
    view: VariablesView,
    catalog_generation: u64,
    count: usize,
    next_index: usize = 0,

    pub fn next(self: *DescriptorIterator) VariableError!?VariableDescriptor {
        if (self.catalog_generation != self.view.version()) return error.Stale;
        if (self.next_index >= self.count) return null;
        const hdr = protocol.readHeader(self.view.client.mem.view) orelse return error.InvalidData;
        const before = readCatalog(hdr) orelse return error.InvalidData;
        if (!Catalog.eql(before, self.view.client.catalog)) return error.LayoutChanged;
        const index = self.next_index;
        const raw = protocol.readVarHeader(self.view.client.mem.view, hdr, index) orelse
            return error.InvalidData;
        const result = parseVariableDescriptor(raw, index) orelse return error.InvalidData;
        const after = readCatalog(hdr) orelse return error.LayoutChanged;
        if (!Catalog.eql(before, after)) return error.LayoutChanged;
        self.next_index += 1;
        return result;
    }
};

fn parseVariable(
    raw: *const protocol.VarHeader,
    native_index: usize,
    row_len: usize,
    catalog_generation: u64,
) ?Variable {
    const var_type = raw.varType() orelse return null;
    if (raw.offset < 0 or raw.count <= 0) return null;
    const count: usize = @intCast(raw.count);
    const start: usize = @intCast(raw.offset);
    const size = variableByteSize(var_type) orelse return null;
    const total = std.math.mul(usize, count, size) catch return null;
    const end = std.math.add(usize, start, total) catch return null;
    if (end > row_len) return null;
    return .{
        .native_index = native_index,
        .catalog_generation = catalog_generation,
        .var_type = var_type,
        .count = count,
        .start = start,
        .end = end,
    };
}

fn parseVariableDescriptor(raw: *const protocol.VarHeader, native_index: usize) ?VariableDescriptor {
    const var_type = raw.varType() orelse return null;
    if (raw.offset < 0 or raw.count <= 0) return null;
    const name = std.mem.sliceTo(&raw.name, 0);
    const description = std.mem.sliceTo(&raw.desc, 0);
    const unit = std.mem.sliceTo(&raw.unit, 0);
    var result = VariableDescriptor{
        .native_index = native_index,
        .var_type = var_type,
        .offset = @intCast(raw.offset),
        .count = @intCast(raw.count),
        .count_as_time = raw.count_as_time != 0,
        .name_buffer = @splat(0),
        .name_len = @intCast(name.len),
        .description_buffer = @splat(0),
        .description_len = @intCast(description.len),
        .unit_buffer = @splat(0),
        .unit_len = @intCast(unit.len),
    };
    @memcpy(result.name_buffer[0..name.len], name);
    @memcpy(result.description_buffer[0..description.len], description);
    @memcpy(result.unit_buffer[0..unit.len], unit);
    return result;
}

fn readCatalog(hdr: *const protocol.Header) ?Catalog {
    const num_vars = readSharedI32(&hdr.num_vars);
    const var_header_offset = readSharedI32(&hdr.var_header_offset);
    const buf_len = readSharedI32(&hdr.buf_len);
    if (num_vars < 0 or var_header_offset < 0 or buf_len <= 0) return null;
    return .{
        .num_vars = num_vars,
        .var_header_offset = var_header_offset,
        .buf_len = buf_len,
    };
}

fn decodeScalar(var_type: protocol.VarType, data: []const u8) ?VariableValue {
    const size = variableByteSize(var_type) orelse return null;
    if (data.len < size) return null;
    return switch (var_type) {
        .char => .{ .char = data[0] },
        .bool => .{ .bool = data[0] != 0 },
        .int => .{ .int = std.mem.readInt(i32, data[0..4], .little) },
        .bit_field => .{ .bit_field = std.mem.readInt(u32, data[0..4], .little) },
        .float => .{ .float = @bitCast(std.mem.readInt(u32, data[0..4], .little)) },
        .double => .{ .double = @bitCast(std.mem.readInt(u64, data[0..8], .little)) },
        .count => null,
    };
}

fn variableByteSize(var_type: protocol.VarType) ?usize {
    return switch (var_type) {
        .char, .bool => 1,
        .int, .bit_field, .float => 4,
        .double => 8,
        .count => null,
    };
}

fn fixtureClient(
    mem: []u8,
    row_buffer: []u8,
    var_type: protocol.VarType,
    count: i32,
    name: []const u8,
) Client {
    @memset(mem, 0);
    const hdr: *protocol.Header = @ptrCast(@alignCast(mem.ptr));
    hdr.* = testing.initHeader(.{
        .status = protocol.status_connected,
        .session_info_update = 1,
        .num_vars = 1,
        .buf_len = @intCast(row_buffer.len),
        .var_buf = .{
            .{ .tick_count = 1, .buf_offset = 300, .tick_count_begin = 1, ._pad = 0 },
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
    });
    return .{
        .mem = .{ .view = mem },
        .allocator = std.testing.allocator,
        .row_buffer = row_buffer,
        .scratch_buffer = row_buffer,
        .catalog = readCatalog(hdr).?,
        .last_tick = 1,
        .connected = true,
        .owns_buffers = false,
    };
}

test "header facade exposes selected values" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.tick_rate = 60;

    try std.testing.expectEqual(@as(?i32, protocol.header_version), client.header().version());
    try std.testing.expectEqual(@as(?i32, 60), client.header().tickRate());
    try std.testing.expectEqual(@as(usize, 1), client.header().variablesLen());
    try std.testing.expect(client.header().isConnected());
}

test "descriptor iterator preserves native indices and metadata" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    var descriptors = try client.variables().descriptors();
    const descriptor = (try descriptors.next()).?;
    try std.testing.expectEqual(@as(usize, 0), descriptor.native_index);
    try std.testing.expectEqualStrings("Gear", descriptor.name());
    try std.testing.expect((try descriptors.next()) == null);
}

test "value returns scalar and borrowed array" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var scalar_row: [4]u8 = undefined;
    std.mem.writeInt(i32, &scalar_row, 4, .little);
    var scalar_client = fixtureClient(&mem, &scalar_row, .int, 1, "Gear");
    const scalar_handle = (try scalar_client.variables().find("Gear")).?;
    const scalar = try scalar_client.variables().value(scalar_handle);
    try std.testing.expectEqual(@as(i32, 4), scalar.int);

    var array_row: [8]u8 = undefined;
    std.mem.writeInt(i32, array_row[0..4], 5, .little);
    std.mem.writeInt(i32, array_row[4..8], 6, .little);
    var array_client = fixtureClient(&mem, &array_row, .int, 2, "Pair");
    const array_handle = try array_client.variables().at(0);
    const array = (try array_client.variables().value(array_handle)).array;
    try std.testing.expectEqual(@as(usize, 2), array.count);
    try std.testing.expectEqual(@as(i32, 6), array.value(1).?.int);
}

test "value uses caller cached metadata on hot path" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = undefined;
    std.mem.writeInt(i32, &row, 7, .little);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    const handle = (try client.variables().find("Gear")).?;
    try std.testing.expectEqual(@as(i32, 7), (try client.variables().value(handle)).int);
    const raw: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    raw.offset = 999;

    // The hot path uses metadata paired with the last successful poll, not volatile headers.
    try std.testing.expectEqual(@as(i32, 7), (try client.variables().value(handle)).int);
}

test "session update does not invalidate telemetry handle" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    const handle = (try client.variables().find("Gear")).?;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.session_info_update = 2;
    const raw: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    raw.offset = 999;
    try std.testing.expectEqual(@as(i32, 0), (try client.variables().value(handle)).int);
    try std.testing.expectEqual(PollStatus.unchanged, client.poll());
    try std.testing.expectEqual(@as(u64, 1), client.variables().version());
}

test "successful poll advances catalog generation on structural change" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    const old_handle = (try client.variables().find("Gear")).?;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.var_header_offset += protocol.var_header_stride;

    try std.testing.expectEqual(PollStatus.updated, client.poll());
    try std.testing.expectEqual(@as(u64, 2), client.variables().version());
    try std.testing.expect(client.variables().value(old_handle) == error.Stale);
}

test "value validates native index and row bounds" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .double, 1, "TooWide");
    try std.testing.expect(client.variables().at(1) == error.IndexOutOfBounds);
    try std.testing.expect(client.variables().at(0) == error.InvalidData);
}

test "poll skips row copy for unchanged tick" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = .{ 1, 2, 3, 4 };
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    mem[300] = 99;
    const raw: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    raw.offset = 999;

    try std.testing.expectEqual(PollStatus.unchanged, client.poll());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, client.row_buffer);
}

test "poll reports stale after configured no-update timeout" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.configureLiveness(std.testing.io, std.Io.Duration.fromMilliseconds(1));
    try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(2), .awake);

    try std.testing.expectEqual(PollStatus.stale, client.poll());
    try std.testing.expect(!client.isConnected());
}

test "poll treats tick rollback as a reset update" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    const handle = (try client.variables().find("Gear")).?;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.var_buf[0].tick_count = 0;
    hdr.var_buf[0].tick_count_begin = 0;
    mem[300] = 42;

    try std.testing.expectEqual(PollStatus.updated, client.poll());
    try std.testing.expectEqual(@as(?i32, 0), client.last_tick);
    try std.testing.expectEqual(@as(u8, 42), client.row_buffer[0]);
    try std.testing.expectEqual(@as(u64, 2), client.variables().version());
    try std.testing.expect(client.variables().value(handle) == error.Stale);
}

test "new frame polling does not inspect descriptors" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    const handle = (try client.variables().find("Gear")).?;
    const raw: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    raw.offset = 999;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.var_buf[0].tick_count = 2;
    hdr.var_buf[0].tick_count_begin = 2;
    std.mem.writeInt(i32, mem[300..304], 8, .little);

    try std.testing.expectEqual(PollStatus.updated, client.poll());
    try std.testing.expectEqual(@as(u64, 1), client.variables().version());
    try std.testing.expectEqual(@as(i32, 8), (try client.variables().value(handle)).int);
}

test "poll transactionally resizes owned row buffers" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.buf_len = 8;
    hdr.var_buf[0].tick_count = 2;
    hdr.var_buf[0].tick_count_begin = 2;
    mem[300] = 77;

    try std.testing.expectEqual(PollStatus.updated, client.poll());
    defer {
        client.allocator.free(client.row_buffer);
        client.allocator.free(client.scratch_buffer);
    }
    try std.testing.expect(client.owns_buffers);
    try std.testing.expectEqual(@as(usize, 8), client.row_buffer.len);
    try std.testing.expectEqual(@as(u8, 77), client.row_buffer[0]);
    try std.testing.expectEqual(@as(u64, 2), client.variables().version());
}

test "failed resize preserves existing row buffers" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = .{ 1, 2, 3, 4 };
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    var no_space: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_space);
    client.allocator = fixed.allocator();
    const original_row = client.row_buffer.ptr;
    const original_scratch = client.scratch_buffer.ptr;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.buf_len = 8;
    hdr.var_buf[0].tick_count = 2;
    hdr.var_buf[0].tick_count_begin = 2;

    try std.testing.expectEqual(PollStatus.rebuild_failed, client.poll());
    try std.testing.expect(client.isConnected());
    try std.testing.expectEqual(original_row, client.row_buffer.ptr);
    try std.testing.expectEqual(original_scratch, client.scratch_buffer.ptr);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, client.row_buffer);
}

test "descriptor iterator is invalidated by catalog generation" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    var iterator = try client.variables().descriptors();
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.num_vars = 0;
    try std.testing.expectEqual(PollStatus.updated, client.poll());
    try std.testing.expect(iterator.next() == error.Stale);
}

test "reconnection invalidates handles even when tick is unchanged" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var scratch: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    client.scratch_buffer = &scratch;
    const handle = (try client.variables().find("Gear")).?;
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.status = 0;
    try std.testing.expectEqual(PollStatus.disconnected, client.poll());
    hdr.status = protocol.status_connected;

    try std.testing.expectEqual(PollStatus.updated, client.poll());
    try std.testing.expectEqual(@as(u64, 2), client.variables().version());
    try std.testing.expect(client.variables().value(handle) == error.Stale);
}

test "scalar decoder preserves every IRSDK wire type" {
    try std.testing.expectEqual(@as(u8, 'z'), decodeScalar(.char, "z").?.char);
    try std.testing.expect(decodeScalar(.bool, &.{1}).?.bool);

    var word: [4]u8 = undefined;
    std.mem.writeInt(i32, &word, -12, .little);
    try std.testing.expectEqual(@as(i32, -12), decodeScalar(.int, &word).?.int);
    std.mem.writeInt(u32, &word, 0xa5a5, .little);
    try std.testing.expectEqual(@as(u32, 0xa5a5), decodeScalar(.bit_field, &word).?.bit_field);
    std.mem.writeInt(u32, &word, @bitCast(@as(f32, 3.5)), .little);
    try std.testing.expectEqual(@as(f32, 3.5), decodeScalar(.float, &word).?.float);

    var double_word: [8]u8 = undefined;
    std.mem.writeInt(u64, &double_word, @bitCast(@as(f64, -9.25)), .little);
    try std.testing.expectEqual(@as(f64, -9.25), decodeScalar(.double, &double_word).?.double);
}

test "poll clears connected state when status is clear" {
    var mem: [512]u8 align(@alignOf(protocol.Header)) = undefined;
    var row: [4]u8 = @splat(0);
    var client = fixtureClient(&mem, &row, .int, 1, "Gear");
    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.status = 0;
    try std.testing.expectEqual(PollStatus.disconnected, client.poll());
    try std.testing.expect(!client.isConnected());
}

test "connect and deinit release resources" {
    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var connected = client;
        connected.deinit();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed, error.InvalidHeader => {},
        else => return err,
    }
}
