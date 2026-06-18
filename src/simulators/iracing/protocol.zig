//! iRacing SDK (IRSDK) shared-memory layout.
//!
//! Reference: iRacing `irsdk_defines.h` (IRSDK_VER = 2) and community clients such as
//! pyirsdk, which track header extensions (cur_buf index, tick_count_begin).

const std = @import("std");

pub const mem_map_name = "Local\\IRSDKMemMapFileName";
pub const data_valid_event_name = "Local\\IRSDKDataValidEvent";
pub const header_version = 2;
pub const max_bufs = 4;
pub const max_string = 32;
pub const max_desc = 64;
pub const var_header_stride = 144;

pub const status_connected: i32 = 1;

pub const VarType = enum(i32) {
    char = 0,
    bool = 1,
    int = 2,
    bit_field = 3,
    float = 4,
    double = 5,

    pub fn byteSize(self: VarType) usize {
        return switch (self) {
            .char, .bool => 1,
            .int, .bit_field, .float => 4,
            .double => 8,
        };
    }
};

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
        return self.status & status_connected != 0;
    }

    pub fn sessionInfo(self: *const Header, mem: []const u8) ?[]const u8 {
        if (self.session_info_len <= 0) return null;
        const start: usize = @intCast(self.session_info_offset);
        const end = start + @as(usize, @intCast(self.session_info_len));
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
        if (self.type < 0 or self.type >= @intFromEnum(VarType.double) + 1) return null;
        return @enumFromInt(self.type);
    }
};

pub fn readHeader(mem: []const u8) ?*const Header {
    if (mem.len < @sizeOf(Header)) return null;
    const header: *const Header = @ptrCast(@alignCast(mem.ptr));
    if (header.ver < 1 or header.num_buf <= 0 or header.num_buf > max_bufs) return null;
    return header;
}

pub fn readVarHeader(mem: []const u8, header: *const Header, index: usize) ?*const VarHeader {
    if (index >= @as(usize, @intCast(header.num_vars))) return null;
    const offset = @as(usize, @intCast(header.var_header_offset)) + index * var_header_stride;
    if (offset + var_header_stride > mem.len) return null;
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
    const count = @min(@as(usize, @intCast(header.num_buf)), max_bufs);
    for (header.var_buf[0..count]) |*buf| {
        if (buf.buf_offset <= 0) continue;
        if (buf.tick_count > best_tick) {
            best_tick = buf.tick_count;
            best = buf;
        }
    }
    return best;
}

/// Copy the active telemetry row from shared memory into `dest`, retrying on torn reads.
pub fn copyLatestRow(mem: []const u8, header: *const Header, dest: []u8) bool {
    const var_buf = latestVarBuf(header) orelse return false;
    const src_start: usize = @intCast(var_buf.buf_offset);
    const len: usize = @intCast(header.buf_len);
    if (src_start + len > mem.len) return false;
    if (len > dest.len) return false;

    const src = mem[src_start..][0..len];
    var attempts: u8 = 0;
    while (attempts < 4) : (attempts += 1) {
        const tick_begin = var_buf.tick_count_begin;
        @memcpy(dest[0..len], src);
        if (var_buf.tick_count == tick_begin) return true;
    }
    @memcpy(dest[0..len], src);
    return true;
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
