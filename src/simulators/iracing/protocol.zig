//! iRacing SDK (IRSDK) shared-memory layout.
//!
//! Reference: iRacing `irsdk_defines.h` (IRSDK_VER = 2) and community clients such as
//! pyirsdk, which track header extensions (cur_buf index, tick_count_begin).

const std = @import("std");
const enums = @import("enums.zig");

pub const mem_map_name = "Local\\IRSDKMemMapFileName";
pub const data_valid_event_name = "Local\\IRSDKDataValidEvent";
pub const header_version = 2;
pub const max_bufs = 4;
pub const max_string = 32;
pub const max_desc = 64;
pub const var_header_stride = 144;

pub const status_connected: i32 = 1;

/// Read a simulator-owned shared-memory integer without allowing the compiler to cache it.
pub fn readSharedI32(ptr: *const i32) i32 {
    const shared: *const volatile i32 = @ptrCast(ptr);
    return shared.*;
}

pub const VarType = enums.VarType;

pub const Header = extern struct {
    ver: i32,
    status: i32,
    tick_rate: i32,
    session_info_update: i32,
    session_info_len: i32,
    session_info_offset: i32,
    num_vars: i32,
    var_header_offset: i32,
    num_buf: i32,
    buf_len: i32,
    cur_buf_tick_count: i32,
    cur_buf: u8,
    _pad: [3]u8,
    var_buf: [max_bufs]VarBuf,

    pub fn isConnected(self: *const Header) bool {
        return readSharedI32(&self.status) & status_connected != 0;
    }

    pub fn sessionInfo(self: *const Header, mem: []const u8) ?[]const u8 {
        const len_value = readSharedI32(&self.session_info_len);
        const offset_value = readSharedI32(&self.session_info_offset);
        if (len_value <= 0 or offset_value < 0) return null;
        const start: usize = @intCast(offset_value);
        const len: usize = @intCast(len_value);
        const end = std.math.add(usize, start, len) catch return null;
        if (end > mem.len) return null;
        return mem[start..end];
    }
};

pub const VarBuf = extern struct {
    tick_count: i32,
    buf_offset: i32,
    tick_count_begin: i32,
    _pad: i32,
};

pub const RowSource = struct {
    buffer: *const VarBuf,
    tick_count: i32,
    offset: usize,
};

pub const VarHeader = extern struct {
    type: i32,
    offset: i32,
    count: i32,
    count_as_time: u8,
    _pad: [3]u8,
    name: [max_string]u8,
    desc: [max_desc]u8,
    unit: [max_string]u8,

    pub fn nameSlice(self: *const VarHeader) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    pub fn varType(self: *const VarHeader) ?VarType {
        if (self.type < 0 or self.type >= @intFromEnum(VarType.count)) return null;
        return @enumFromInt(self.type);
    }
};

pub fn readHeader(mem: []const u8) ?*const Header {
    if (mem.len < @sizeOf(Header)) return null;
    const header: *const Header = @ptrCast(@alignCast(mem.ptr));
    const ver = readSharedI32(&header.ver);
    const num_buf = readSharedI32(&header.num_buf);
    const buf_len = readSharedI32(&header.buf_len);
    const num_vars = readSharedI32(&header.num_vars);
    if (ver != header_version or num_buf <= 0 or num_buf > max_bufs) return null;
    if (buf_len <= 0 or num_vars < 0) return null;
    return header;
}

pub fn readVarHeader(mem: []const u8, header: *const Header, index: usize) ?*const VarHeader {
    const num_vars_value = readSharedI32(&header.num_vars);
    const base_value = readSharedI32(&header.var_header_offset);
    if (num_vars_value < 0 or base_value < 0) return null;
    if (index >= @as(usize, @intCast(num_vars_value))) return null;
    const stride_offset = std.math.mul(usize, index, var_header_stride) catch return null;
    const offset = std.math.add(usize, @intCast(base_value), stride_offset) catch return null;
    const end = std.math.add(usize, offset, var_header_stride) catch return null;
    if (end > mem.len or offset % @alignOf(VarHeader) != 0) return null;
    return @ptrCast(@alignCast(mem.ptr + offset));
}

/// Pick the telemetry row buffer with the highest tick count (most recently written).
///
/// We intentionally do not use `Header.cur_buf` alone: the sim can advance `cur_buf` before
/// `tick_count_begin` catches up on the new slot. Scanning tick counts plus the torn-read
/// check in `copyLatestRow` matches community clients (e.g. pyirsdk) and avoids stale rows.
pub fn latestVarBuf(header: *const Header) ?*const VarBuf {
    var best: ?*const VarBuf = null;
    var best_tick: i32 = std.math.minInt(i32);
    const num_buf_value = readSharedI32(&header.num_buf);
    if (num_buf_value <= 0 or num_buf_value > max_bufs) return null;
    const count: usize = @intCast(num_buf_value);
    for (header.var_buf[0..count]) |*buf| {
        const buf_offset = readSharedI32(&buf.buf_offset);
        const tick_count = readSharedI32(&buf.tick_count);
        if (buf_offset <= 0) continue;
        if (tick_count > best_tick) {
            best_tick = tick_count;
            best = buf;
        }
    }
    return best;
}

/// Snapshot the currently newest row's identity. Callers can compare `tick_count`
/// before deciding whether copying the row is necessary.
pub fn latestRowSource(mem: []const u8, header: *const Header) ?RowSource {
    const buffer = latestVarBuf(header) orelse return null;
    const offset_value = readSharedI32(&buffer.buf_offset);
    const len_value = readSharedI32(&header.buf_len);
    if (offset_value < 0 or len_value <= 0) return null;
    const offset: usize = @intCast(offset_value);
    const len: usize = @intCast(len_value);
    const end = std.math.add(usize, offset, len) catch return null;
    if (end > mem.len) return null;
    return .{
        .buffer = buffer,
        .tick_count = readSharedI32(&buffer.tick_count),
        .offset = offset,
    };
}

/// Copy a selected telemetry row into owned storage, rejecting a row that was
/// being written or stopped being the selected tick during the copy.
pub fn copyRow(mem: []const u8, header: *const Header, source: RowSource, dest: []u8) bool {
    const len_value = readSharedI32(&header.buf_len);
    if (len_value <= 0) return false;
    const len: usize = @intCast(len_value);
    const end = std.math.add(usize, source.offset, len) catch return false;
    if (end > mem.len or len > dest.len) return false;

    const src = mem[source.offset..end];
    var attempts: u8 = 0;
    while (attempts < 4) : (attempts += 1) {
        const tick_begin = readSharedI32(&source.buffer.tick_count_begin);
        @memcpy(dest[0..len], src);
        const tick_begin_after = readSharedI32(&source.buffer.tick_count_begin);
        const tick_end = readSharedI32(&source.buffer.tick_count);
        if (tick_begin == source.tick_count and
            tick_begin_after == source.tick_count and
            tick_end == source.tick_count)
        {
            return true;
        }
    }
    return false;
}

/// Copy the active telemetry row from shared memory into `dest`, retrying on torn reads.
pub fn copyLatestRow(mem: []const u8, header: *const Header, dest: []u8) bool {
    const source = latestRowSource(mem, header) orelse return false;
    return copyRow(mem, header, source, dest);
}

const testing = @import("testing.zig");

test "header layout size" {
    try std.testing.expectEqual(@as(usize, 112), @sizeOf(Header));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(VarBuf));
    try std.testing.expectEqual(@as(usize, 144), var_header_stride);
}

test "read header from bytes" {
    var mem: [256]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .status = status_connected,
        .tick_rate = 60,
        .num_vars = 1,
        .var_buf = .{
            .{
                .tick_count = 10,
                .buf_offset = 200,
                .tick_count_begin = 10,
                ._pad = 0,
            },
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
        },
    });

    const vh: *VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(Header)]));
    vh.* = testing.initVarHeader(.{
        .type = @intFromEnum(VarType.int),
        .name = "Gear",
    });

    const parsed = readHeader(&mem).?;
    try std.testing.expect(parsed.isConnected());
    try std.testing.expectEqual(@as(i32, 1), parsed.num_vars);
    try std.testing.expectEqual(@as(i32, 10), latestVarBuf(parsed).?.tick_count);

    const gear_header = readVarHeader(&mem, parsed, 0).?;
    try std.testing.expectEqualStrings("Gear", gear_header.nameSlice());
}

test "copyLatestRow detects consistent tick and copies payload" {
    var mem: [512]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .buf_len = 8,
        .var_buf = .{
            .{
                .tick_count = 5,
                .buf_offset = 200,
                .tick_count_begin = 5,
                ._pad = 0,
            },
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
        },
    });

    const payload = mem[200..208];
    payload[0] = 0xAA;
    payload[1] = 0xBB;

    var dest: [8]u8 = undefined;
    try std.testing.expect(copyLatestRow(&mem, hdr, &dest));
    try std.testing.expectEqual(@as(u8, 0xAA), dest[0]);
    try std.testing.expectEqual(@as(u8, 0xBB), dest[1]);
}

test "latest row source selects highest tick across buffers" {
    var mem: [512]u8 = undefined;
    @memset(&mem, 0);
    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .num_buf = 3,
        .buf_len = 4,
        .var_buf = .{
            .{ .tick_count = 8, .buf_offset = 200, .tick_count_begin = 8, ._pad = 0 },
            .{ .tick_count = 12, .buf_offset = 204, .tick_count_begin = 12, ._pad = 0 },
            .{ .tick_count = 10, .buf_offset = 208, .tick_count_begin = 10, ._pad = 0 },
            std.mem.zeroes(VarBuf),
        },
    });
    mem[204] = 0x5a;

    const source = latestRowSource(&mem, hdr).?;
    try std.testing.expectEqual(@as(i32, 12), source.tick_count);
    var dest: [4]u8 = undefined;
    try std.testing.expect(copyRow(&mem, hdr, source, &dest));
    try std.testing.expectEqual(@as(u8, 0x5a), dest[0]);
}

test "copyLatestRow returns false when buffer offset is out of range" {
    var mem: [256]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .buf_len = 64,
        .var_buf = .{
            .{
                .tick_count = 1,
                .buf_offset = 300,
                .tick_count_begin = 1,
                ._pad = 0,
            },
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
        },
    });

    var dest: [64]u8 = undefined;
    try std.testing.expect(!copyLatestRow(&mem, hdr, &dest));
}

test "copyLatestRow rejects an inconsistent row after retries" {
    var mem: [256]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .buf_len = 8,
        .var_buf = .{
            .{
                .tick_count = 5,
                .buf_offset = 200,
                .tick_count_begin = 4,
                ._pad = 0,
            },
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
            std.mem.zeroes(VarBuf),
        },
    });

    var dest: [8]u8 = undefined;
    try std.testing.expect(!copyLatestRow(&mem, hdr, &dest));
}

test "header and offset validation rejects invalid signed fields" {
    var mem: [256]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{});
    try std.testing.expect(readHeader(&mem) != null);

    hdr.ver = header_version + 1;
    try std.testing.expect(readHeader(&mem) == null);
    hdr.ver = header_version;

    hdr.session_info_offset = -1;
    hdr.session_info_len = 8;
    try std.testing.expect(hdr.sessionInfo(&mem) == null);

    hdr.num_vars = 1;
    hdr.var_header_offset = -1;
    try std.testing.expect(readVarHeader(&mem, hdr, 0) == null);
}
