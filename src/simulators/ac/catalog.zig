//! Generic, name-based access over the fixed Assetto Corsa physics/graphics/static pages.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Which shared-memory page a field lives on.
pub const Page = enum { physics, graphics, static };

/// Decoded element type for a catalog field.
pub const FieldType = enum {
    f32,
    i32,
    u32,
    /// A fixed-size, NUL-terminated UTF-16LE `wchar_t` buffer (`[N]u16`).
    wstring,

    pub fn byteSize(self: FieldType) usize {
        return switch (self) {
            .f32, .i32, .u32 => 4,
            .wstring => 2,
        };
    }

    pub fn isNumeric(self: FieldType) bool {
        return self != .wstring;
    }
};

pub const FieldDescriptor = struct {
    name: []const u8,
    page: Page,
    offset: usize,
    field_type: FieldType,
    /// 1 for numeric scalars; N for numeric arrays or wstring code-unit length.
    count: usize,
};

const Classification = struct { field_type: FieldType, count: usize };

fn classifyScalar(comptime T: type) ?FieldType {
    return switch (T) {
        f32 => .f32,
        i32 => .i32,
        u32 => .u32,
        else => null,
    };
}

/// Catalog numeric scalars, 1-D numeric arrays, and `[N]u16` wstrings. Multi-dimensional arrays
/// are skipped and remain available through typed struct access.
fn classify(comptime T: type) ?Classification {
    if (classifyScalar(T)) |ft| return .{ .field_type = ft, .count = 1 };
    switch (@typeInfo(T)) {
        .array => |arr| {
            if (arr.child == u16) return .{ .field_type = .wstring, .count = arr.len };
            const elem = classifyScalar(arr.child) orelse return null;
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
pub fn decodeNumber(field: FieldDescriptor, page_bytes: []const u8) ?f64 {
    if (!field.field_type.isNumeric()) return null;
    const size = field.field_type.byteSize();
    if (field.offset + size > page_bytes.len) return null;
    const data = page_bytes[field.offset..][0..size];
    return switch (field.field_type) {
        .f32 => @as(f64, @as(f32, @bitCast(std.mem.readInt(u32, data[0..4], .little)))),
        .i32 => @floatFromInt(std.mem.readInt(i32, data[0..4], .little)),
        .u32 => @floatFromInt(std.mem.readInt(u32, data[0..4], .little)),
        .wstring => unreachable,
    };
}

/// Decode a wstring `field` into `out` as UTF-8, truncating at the NUL terminator.
pub fn decodeWString(field: FieldDescriptor, page_bytes: []const u8, out: []u8) ?[]const u8 {
    if (field.field_type != .wstring) return null;
    const total = field.count * 2;
    if (field.offset + total > page_bytes.len) return null;
    return protocol.wcharToUtf8(page_bytes[field.offset..][0..total], out);
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

test "catalog discovers AC-specific and shared fields" {
    try std.testing.expect(field_count > 80);
    try std.testing.expect(find("speed_kmh") != null);
    try std.testing.expect(find("rpms") != null);
    try std.testing.expect(find("wind_speed") != null);
    try std.testing.expect(find("track_spline_length") != null);
    try std.testing.expect(find("track_configuration") != null);
    try std.testing.expect(find("car_model") != null);
    try std.testing.expect(find("track") != null);
    try std.testing.expect(find("tyre_contact_point") == null);
}

test "catalog field metadata matches the struct layout" {
    const speed = find("speed_kmh").?;
    try std.testing.expectEqual(Page.physics, speed.page);
    try std.testing.expectEqual(FieldType.f32, speed.field_type);
    try std.testing.expectEqual(@as(usize, 1), speed.count);
    try std.testing.expectEqual(@offsetOf(protocol.Physics, "speed_kmh"), speed.offset);

    const wind = find("wind_direction").?;
    try std.testing.expectEqual(Page.graphics, wind.page);
    try std.testing.expectEqual(FieldType.f32, wind.field_type);

    const track = find("track").?;
    try std.testing.expectEqual(Page.static, track.page);
    try std.testing.expectEqual(FieldType.wstring, track.field_type);
    try std.testing.expectEqual(@as(usize, 33), track.count);
}

test "decodeNumber reads numeric fields and ignores wstrings" {
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

test "decodeWString converts a UTF-16LE buffer and ignores numerics" {
    var stat: protocol.Static = .{};
    const name = std.unicode.utf8ToUtf16LeStringLiteral("Ferrari 458");
    @memcpy(stat.car_model[0..name.len], name);
    const bytes = std.mem.asBytes(&stat);

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ferrari 458", decodeWString(find("car_model").?, bytes, &out).?);
    try std.testing.expect(decodeWString(find("track_spline_length").?, bytes, &out) == null);
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
