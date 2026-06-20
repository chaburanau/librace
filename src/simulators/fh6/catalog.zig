//! Generic, name-based access over the fixed FH6 Data Out packet.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const Page = enum { packet };

pub const FieldType = enum {
    f32,
    i32,
    u32,
    u16,
    u8,
    i8,

    pub fn byteSize(self: FieldType) usize {
        return switch (self) {
            .f32, .i32, .u32 => 4,
            .u16 => 2,
            .u8, .i8 => 1,
        };
    }

    pub fn isNumeric(self: FieldType) bool {
        _ = self;
        return true;
    }
};

pub const FieldDescriptor = struct {
    name: []const u8,
    page: Page,
    offset: usize,
    field_type: FieldType,
    count: usize,
};

const Classification = struct { field_type: FieldType, count: usize };

fn classifyInt(comptime T: type) ?FieldType {
    return switch (T) {
        i32 => .i32,
        u32 => .u32,
        u16 => .u16,
        u8 => .u8,
        i8 => .i8,
        else => null,
    };
}

fn classifyScalar(comptime T: type) ?FieldType {
    if (classifyInt(T)) |ft| return ft;
    return switch (T) {
        f32 => .f32,
        else => null,
    };
}

fn classify(comptime T: type) ?Classification {
    if (classifyScalar(T)) |ft| return .{ .field_type = ft, .count = 1 };
    switch (@typeInfo(T)) {
        .array => |arr| {
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

pub const packet_fields = buildCatalog(protocol.DashPacket, .packet);
pub const all_fields = packet_fields;
pub const field_count = all_fields.len;

pub fn find(name: []const u8) ?FieldDescriptor {
    for (all_fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

pub fn decodeNumber(field: FieldDescriptor, page_bytes: []const u8) ?f64 {
    const size = field.field_type.byteSize();
    if (field.offset + size > page_bytes.len) return null;
    const data = page_bytes[field.offset..][0..size];
    return switch (field.field_type) {
        .f32 => @as(f64, @as(f32, @bitCast(std.mem.readInt(u32, data[0..4], .little)))),
        .i32 => @floatFromInt(std.mem.readInt(i32, data[0..4], .little)),
        .u32 => @floatFromInt(std.mem.readInt(u32, data[0..4], .little)),
        .u16 => @floatFromInt(std.mem.readInt(u16, data[0..2], .little)),
        .u8 => @floatFromInt(data[0]),
        .i8 => @floatFromInt(@as(i8, @bitCast(data[0]))),
    };
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

test "catalog discovers FH6 fields" {
    try std.testing.expect(field_count > 80);
    try std.testing.expect(find("speed") != null);
    try std.testing.expect(find("current_engine_rpm") != null);
    try std.testing.expect(find("car_group") != null);
    try std.testing.expect(find("smashable_mass") != null);
    try std.testing.expectEqual(@offsetOf(protocol.DashPacket, "gear"), find("gear").?.offset);
}
