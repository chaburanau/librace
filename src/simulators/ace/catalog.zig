//! Generic, name-based access over the fixed AC Evo physics/graphics/static pages.
//!
//! Unlike iRacing (a per-session variable catalog discovered at runtime), AC Evo exposes
//! fixed C structs. This module reflects over those structs at comptime to build a flat,
//! immutable catalog keyed by each field's protocol name. It powers generic lookups
//! (`getNumber`/`getString`/`getRaw`) and discovery (name iteration) without forcing callers
//! to hard-code byte offsets or maintain per-field accessors — adding or removing a field in
//! `protocol.zig` automatically updates what is reachable here. Typed struct access stays
//! available via the client for callers that prefer it.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Which shared-memory page a field lives on.
pub const Page = enum { physics, graphics, static };

/// Decoded element type for a catalog field.
pub const FieldType = enum {
    f32,
    i32,
    u32,
    i16,
    u16,
    i8,
    u8,
    u64,
    bool,
    /// A fixed-size, NUL-terminated C char buffer (`[N]u8`).
    string,

    pub fn byteSize(self: FieldType) usize {
        return switch (self) {
            .i8, .u8, .bool, .string => 1,
            .i16, .u16 => 2,
            .f32, .i32, .u32 => 4,
            .u64 => 8,
        };
    }

    pub fn isNumeric(self: FieldType) bool {
        return self != .string;
    }
};

pub const FieldDescriptor = struct {
    name: []const u8,
    page: Page,
    offset: usize,
    field_type: FieldType,
    /// 1 for numeric scalars; N for a numeric array (`wheel_slip` = 4) or string buffer length.
    count: usize,
};

const Classification = struct { field_type: FieldType, count: usize };

fn classifyScalar(comptime T: type) ?FieldType {
    return switch (T) {
        f32 => .f32,
        i32 => .i32,
        u32 => .u32,
        i16 => .i16,
        u16 => .u16,
        i8 => .i8,
        u8 => .u8,
        u64 => .u64,
        bool => .bool,
        else => null,
    };
}

/// Catalog numeric scalars, 1-D numeric arrays, and `[N]u8` strings. Multi-dimensional
/// arrays and embedded structs are skipped — those are reached through typed struct access.
fn classify(comptime T: type) ?Classification {
    if (classifyScalar(T)) |ft| return .{ .field_type = ft, .count = 1 };
    switch (@typeInfo(T)) {
        .array => |arr| {
            const elem = classifyScalar(arr.child) orelse return null;
            if (elem == .u8) return .{ .field_type = .string, .count = arr.len };
            if (elem == .i8) return null; // signed byte arrays are not strings in these pages
            return .{ .field_type = elem, .count = arr.len };
        },
        else => return null,
    }
}

fn buildCatalog(comptime T: type, comptime page: Page) []const FieldDescriptor {
    comptime {
        var list: []const FieldDescriptor = &.{};
        for (@typeInfo(T).@"struct".fields) |field| {
            const c = classify(field.type) orelse continue;
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

pub const physics_fields = buildCatalog(protocol.Physics, .physics);
pub const graphics_fields = buildCatalog(protocol.Graphics, .graphics);
pub const static_fields = buildCatalog(protocol.Static, .static);

/// Every catalogued field across all three pages, in page order.
pub const all_fields = physics_fields ++ graphics_fields ++ static_fields;

/// Total number of named fields exposed across all pages.
pub const field_count = all_fields.len;

pub fn find(name: []const u8) ?FieldDescriptor {
    for (all_fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

/// Decode the first element of a numeric `field` from `page_bytes` as a lenient `f64`.
/// Returns null for string fields or when the field lies outside `page_bytes`.
pub fn decodeNumber(field: FieldDescriptor, page_bytes: []const u8) ?f64 {
    if (!field.field_type.isNumeric()) return null;
    const size = field.field_type.byteSize();
    if (field.offset + size > page_bytes.len) return null;
    const data = page_bytes[field.offset..][0..size];
    return switch (field.field_type) {
        .f32 => @as(f64, @as(f32, @bitCast(std.mem.readInt(u32, data[0..4], .little)))),
        .i32 => @floatFromInt(std.mem.readInt(i32, data[0..4], .little)),
        .u32 => @floatFromInt(std.mem.readInt(u32, data[0..4], .little)),
        .i16 => @floatFromInt(std.mem.readInt(i16, data[0..2], .little)),
        .u16 => @floatFromInt(std.mem.readInt(u16, data[0..2], .little)),
        .i8 => @floatFromInt(@as(i8, @bitCast(data[0]))),
        .u8 => @floatFromInt(data[0]),
        .u64 => @floatFromInt(std.mem.readInt(u64, data[0..8], .little)),
        .bool => if (data[0] != 0) 1 else 0,
        .string => unreachable,
    };
}

/// Decode a string `field` as its NUL-terminated slice. Null for non-string fields.
pub fn decodeString(field: FieldDescriptor, page_bytes: []const u8) ?[]const u8 {
    if (field.field_type != .string) return null;
    if (field.offset + field.count > page_bytes.len) return null;
    return std.mem.sliceTo(page_bytes[field.offset..][0..field.count], 0);
}

/// Raw little-endian bytes of `field` (whole array/string buffer). Valid until next poll.
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

test "catalog discovers numeric, string, and static fields" {
    try std.testing.expect(field_count > 50);
    // Numeric fields across pages.
    try std.testing.expect(find("speed_kmh") != null);
    try std.testing.expect(find("rpms") != null);
    try std.testing.expect(find("npos") != null);
    try std.testing.expect(find("track_length_m") != null);
    // String fields are now catalogued generically.
    try std.testing.expect(find("driver_name") != null);
    try std.testing.expect(find("car_model") != null);
    try std.testing.expect(find("track") != null);
    // Padding, multi-dimensional arrays, and embedded structs stay excluded.
    try std.testing.expect(find("tyre_contact_point") == null);
    try std.testing.expect(find("tyre_lf") == null);
}

test "catalog field metadata matches the struct layout" {
    const speed = find("speed_kmh").?;
    try std.testing.expectEqual(Page.physics, speed.page);
    try std.testing.expectEqual(FieldType.f32, speed.field_type);
    try std.testing.expectEqual(@as(usize, 1), speed.count);
    try std.testing.expectEqual(@offsetOf(protocol.Physics, "speed_kmh"), speed.offset);

    const wheel_slip = find("wheel_slip").?;
    try std.testing.expectEqual(@as(usize, 4), wheel_slip.count);

    const track = find("track").?;
    try std.testing.expectEqual(Page.static, track.page);
    try std.testing.expectEqual(FieldType.string, track.field_type);
    try std.testing.expectEqual(@as(usize, 33), track.count);
}

test "decodeNumber reads numeric fields and ignores strings" {
    var phys: protocol.Physics = .{};
    phys.speed_kmh = 123.5;
    phys.gear = 4;
    const bytes = std.mem.asBytes(&phys);

    try std.testing.expectApproxEqAbs(
        @as(f64, 123.5),
        decodeNumber(find("speed_kmh").?, bytes).?,
        0.001,
    );
    try std.testing.expectEqual(@as(f64, 4), decodeNumber(find("gear").?, bytes).?);
    try std.testing.expect(decodeNumber(find("track").?, bytes) == null);
}

test "decodeString trims a NUL-terminated buffer and ignores numerics" {
    var stat: protocol.Static = .{};
    const src = "Spa-Francorchamps";
    @memcpy(stat.track[0..src.len], src);
    const bytes = std.mem.asBytes(&stat);

    try std.testing.expectEqualStrings("Spa-Francorchamps", decodeString(find("track").?, bytes).?);
    try std.testing.expect(decodeString(find("track_length_m").?, bytes) == null);
}

test "name iterator visits every catalogued field" {
    var it: NameIterator = .{};
    var count: usize = 0;
    var saw_speed = false;
    var saw_track = false;
    while (it.next()) |name| {
        count += 1;
        if (std.mem.eql(u8, name, "speed_kmh")) saw_speed = true;
        if (std.mem.eql(u8, name, "track")) saw_track = true;
    }
    try std.testing.expectEqual(field_count, count);
    try std.testing.expect(saw_speed and saw_track);
}
