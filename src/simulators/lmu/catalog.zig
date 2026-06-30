//! Generic, name-based access over LMU's player telemetry/session/scoring snapshots.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const Page = enum { telem, session, vehicle };

pub const FieldType = enum {
    f64,
    f32,
    i32,
    u32,
    i16,
    u16,
    i8,
    u8,
    u64,
    bool,
    cstring,

    pub fn byteSize(self: FieldType) usize {
        return switch (self) {
            .f64 => 8,
            .f32, .i32, .u32 => 4,
            .i16, .u16 => 2,
            .i8, .u8, .bool, .cstring => 1,
            .u64 => 8,
        };
    }

    pub fn isNumeric(self: FieldType) bool {
        return self != .cstring;
    }
};

pub const FieldDescriptor = struct {
    name: []const u8,
    page: Page,
    offset: usize,
    field_type: FieldType,
    count: usize,
};

const Classification = struct {
    field_type: FieldType,
    count: usize,
};

fn classifyInt(comptime T: type) ?FieldType {
    return switch (T) {
        i32 => .i32,
        u32 => .u32,
        i16 => .i16,
        u16 => .u16,
        i8 => .i8,
        u8 => .u8,
        u64 => .u64,
        else => switch (@typeInfo(T)) {
            .@"enum" => |e| classifyInt(e.tag_type),
            else => null,
        },
    };
}

fn classifyScalar(comptime T: type) ?FieldType {
    if (classifyInt(T)) |ft| return ft;
    return switch (T) {
        f64 => .f64,
        f32 => .f32,
        bool => .bool,
        else => null,
    };
}

fn classify(comptime name: []const u8, comptime T: type) ?Classification {
    if (classifyScalar(T)) |ft| return .{ .field_type = ft, .count = 1 };
    switch (@typeInfo(T)) {
        .array => |arr| {
            if (arr.child == u8 and isStringField(name)) {
                return .{ .field_type = .cstring, .count = arr.len };
            }
            const elem = classifyScalar(arr.child) orelse return null;
            return .{ .field_type = elem, .count = arr.len };
        },
        else => return null,
    }
}

fn isStringField(comptime name: []const u8) bool {
    return std.mem.endsWith(u8, name, "_name") or
        std.mem.endsWith(u8, name, "_filename") or
        std.mem.eql(u8, name, "vehicle_model") or
        std.mem.eql(u8, name, "track_name") or
        std.mem.eql(u8, name, "vehicle_name") or
        std.mem.eql(u8, name, "driver_name") or
        std.mem.eql(u8, name, "player_name") or
        std.mem.eql(u8, name, "plr_file_name") or
        std.mem.eql(u8, name, "server_name") or
        std.mem.eql(u8, name, "pit_group") or
        std.mem.eql(u8, name, "terrain_name") or
        std.mem.eql(u8, name, "user_data") or
        std.mem.eql(u8, name, "custom_variables") or
        std.mem.eql(u8, name, "steward_results") or
        std.mem.eql(u8, name, "player_profile") or
        std.mem.eql(u8, name, "plugins_folder") or
        std.mem.endsWith(u8, name, "_compound_name");
}

fn buildCatalog(comptime T: type, comptime page: Page) []const FieldDescriptor {
    comptime {
        var list: []const FieldDescriptor = &.{};
        for (@typeInfo(T).@"struct".fields) |field| {
            if (field.name[0] == '_') continue;
            const c = classify(field.name, field.type) orelse continue;
            list = list ++ &[_]FieldDescriptor{.{
                .name = field.name,
                .page = page,
                .offset = @offsetOf(T, field.name),
                .field_type = c.field_type,
                .count = c.count,
            }};
        }
        return list;
    }
}

pub const telem_fields = buildCatalog(protocol.TelemInfoV01, .telem);
pub const session_fields = buildCatalog(protocol.ScoringInfoV01, .session);
pub const vehicle_fields = buildCatalog(protocol.VehicleScoringInfoV01, .vehicle);

pub const all_fields = telem_fields ++ session_fields ++ vehicle_fields;
pub const field_count = all_fields.len;

/// When the same field name appears on multiple pages, generic lookup uses a canonical page.
fn canonicalPage(name: []const u8) ?Page {
    if (std.mem.eql(u8, name, "track_name")) return .session;
    if (std.mem.eql(u8, name, "vehicle_name")) return .telem;
    return null;
}

pub fn findIn(page: Page, name: []const u8) ?FieldDescriptor {
    for (all_fields) |f| {
        if (f.page == page and std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

pub fn find(name: []const u8) ?FieldDescriptor {
    if (canonicalPage(name)) |page| return findIn(page, name);
    for (all_fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

pub fn decodeNumber(field: FieldDescriptor, page_bytes: []const u8) ?f64 {
    if (!field.field_type.isNumeric()) return null;
    const size = field.field_type.byteSize();
    if (field.offset + size > page_bytes.len) return null;
    const data = page_bytes[field.offset..][0..size];
    return switch (field.field_type) {
        .f64 => @as(f64, @bitCast(std.mem.readInt(u64, data[0..8], .little))),
        .f32 => @as(f32, @bitCast(std.mem.readInt(u32, data[0..4], .little))),
        .i32 => @floatFromInt(std.mem.readInt(i32, data[0..4], .little)),
        .u32 => @floatFromInt(std.mem.readInt(u32, data[0..4], .little)),
        .i16 => @floatFromInt(std.mem.readInt(i16, data[0..2], .little)),
        .u16 => @floatFromInt(std.mem.readInt(u16, data[0..2], .little)),
        .i8 => @floatFromInt(@as(i8, @bitCast(data[0]))),
        .u8 => @floatFromInt(data[0]),
        .u64 => @floatFromInt(std.mem.readInt(u64, data[0..8], .little)),
        .bool => if (data[0] != 0) 1 else 0,
        .cstring => unreachable,
    };
}

pub fn decodeString(field: FieldDescriptor, page_bytes: []const u8, out: []u8) ?[]const u8 {
    if (field.field_type != .cstring) return null;
    const total = field.count;
    if (field.offset + total > page_bytes.len) return null;
    return protocol.cstrToUtf8(page_bytes[field.offset..][0..total], out);
}

pub fn rawBytes(field: FieldDescriptor, page_bytes: []const u8) ?[]const u8 {
    const total = field.field_type.byteSize() * field.count;
    if (field.offset + total > page_bytes.len) return null;
    return page_bytes[field.offset..][0..total];
}

pub const NameIterator = struct {
    index: usize = 0,

    pub fn next(self: *NameIterator) ?[]const u8 {
        if (self.index >= all_fields.len) return null;
        defer self.index += 1;
        return all_fields[self.index].name;
    }
};

test "catalog discovers player telemetry, session, and scoring fields" {
    try std.testing.expect(field_count > 180);
    try std.testing.expect(find("gear") != null);
    try std.testing.expect(find("engine_rpm") != null);
    try std.testing.expect(find("regen") != null);
    try std.testing.expect(find("track_name") != null);
    try std.testing.expect(find("driver_name") != null);
    try std.testing.expect(find("best_lap_time") != null);
    try std.testing.expect(find("wheel") == null);
    try std.testing.expect(find("ori") == null);
}

test "catalog metadata matches LMU struct offsets" {
    const rpm = find("engine_rpm").?;
    try std.testing.expectEqual(Page.telem, rpm.page);
    try std.testing.expectEqual(FieldType.f64, rpm.field_type);
    try std.testing.expectEqual(@as(usize, 356), rpm.offset);

    const track = find("track_name").?;
    try std.testing.expectEqual(Page.session, track.page);
    try std.testing.expectEqual(FieldType.cstring, track.field_type);
    try std.testing.expectEqual(@as(usize, 64), track.count);
    try std.testing.expectEqual(@as(usize, 0), track.offset);

    const best = find("best_lap_time").?;
    try std.testing.expectEqual(Page.vehicle, best.page);
    try std.testing.expectEqual(FieldType.f64, best.field_type);
    try std.testing.expectEqual(@as(usize, 144), best.offset);
}

test "decodeNumber and decodeString read owned snapshots" {
    var telem: protocol.TelemInfoV01 = .{};
    telem.engine_rpm = 7200.5;
    telem.gear = 4;
    @memcpy(telem.vehicle_name[0.."Porsche 963".len], "Porsche 963");

    const bytes = std.mem.asBytes(&telem);
    try std.testing.expectApproxEqAbs(@as(f64, 7200.5), decodeNumber(find("engine_rpm").?, bytes).?, 0.001);
    try std.testing.expectEqual(@as(f64, 4), decodeNumber(find("gear").?, bytes).?);

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Porsche 963", decodeString(find("vehicle_name").?, bytes, &out).?);
}
