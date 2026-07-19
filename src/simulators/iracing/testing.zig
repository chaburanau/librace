//! Test-only IRSDK fixture builders.
//!
//! This module is intentionally NOT re-exported from `root.zig`, so these helpers
//! never appear in the public library surface. Test blocks import it directly.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Build a zeroed IRSDK header for unit tests, overriding selected fields.
pub fn initHeader(fields: struct {
    ver: i32 = protocol.header_version,
    status: i32 = 0,
    tick_rate: i32 = 0,
    session_info_update: i32 = 0,
    session_info_len: i32 = 0,
    session_info_offset: i32 = 0,
    num_vars: i32 = 0,
    var_header_offset: i32 = @sizeOf(protocol.Header),
    num_buf: i32 = 1,
    buf_len: i32 = 32,
    cur_buf_tick_count: i32 = 0,
    cur_buf: u8 = 0,
    var_buf: [protocol.max_bufs]protocol.VarBuf = .{std.mem.zeroes(protocol.VarBuf)} ** protocol.max_bufs,
}) protocol.Header {
    var hdr = std.mem.zeroes(protocol.Header);
    hdr.ver = fields.ver;
    hdr.status = fields.status;
    hdr.tick_rate = fields.tick_rate;
    hdr.session_info_update = fields.session_info_update;
    hdr.session_info_len = fields.session_info_len;
    hdr.session_info_offset = fields.session_info_offset;
    hdr.num_vars = fields.num_vars;
    hdr.var_header_offset = fields.var_header_offset;
    hdr.num_buf = fields.num_buf;
    hdr.buf_len = fields.buf_len;
    hdr.cur_buf_tick_count = fields.cur_buf_tick_count;
    hdr.cur_buf = fields.cur_buf;
    hdr.var_buf = fields.var_buf;
    return hdr;
}

/// Build a zeroed var header for unit tests, overriding selected fields.
pub fn initVarHeader(fields: struct {
    type: i32,
    offset: i32 = 0,
    count: i32 = 1,
    count_as_time: bool = false,
    name: []const u8 = "",
    description: []const u8 = "",
    unit: []const u8 = "",
}) protocol.VarHeader {
    var vh = std.mem.zeroes(protocol.VarHeader);
    vh.type = fields.type;
    vh.offset = fields.offset;
    vh.count = fields.count;
    vh.count_as_time = @intFromBool(fields.count_as_time);
    const name_len = @min(fields.name.len, protocol.max_string);
    @memcpy(vh.name[0..name_len], fields.name[0..name_len]);
    const description_len = @min(fields.description.len, protocol.max_desc);
    @memcpy(vh.desc[0..description_len], fields.description[0..description_len]);
    const unit_len = @min(fields.unit.len, protocol.max_string);
    @memcpy(vh.unit[0..unit_len], fields.unit[0..unit_len]);
    return vh;
}
