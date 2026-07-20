const std = @import("std");

/// Trim a fixed-size C char buffer to its NUL-terminated string slice.
pub fn cString(buf: []const u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

/// Slice a fixed-size C char buffer at the first NUL, or through the end when none is present.
pub fn cstr(buf: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
    return buf[0..end];
}

/// Copy a NUL-terminated C string into `out` when it is valid UTF-8.
pub fn cstrToUtf8(src_bytes: []const u8, out: []u8) ?[]const u8 {
    const s = cstr(src_bytes);
    if (!std.unicode.utf8ValidateSlice(s)) return null;
    const len = @min(s.len, out.len);
    @memcpy(out[0..len], s[0..len]);
    return out[0..len];
}

/// Decode a NUL-terminated UTF-16LE code-unit slice into `out` as UTF-8.
pub fn utf16ZToUtf8(wide: []const u16, out: []u8) ?[]const u8 {
    var len: usize = 0;
    while (len < wide.len and wide[len] != 0) : (len += 1) {}
    if (len == 0) return out[0..0];
    const written = std.unicode.utf16LeToUtf8(out, wide[0..len]) catch return null;
    return out[0..written];
}

/// Decode a UTF-16LE (`wchar_t`) byte buffer into `out` as UTF-8, truncating at the NUL terminator.
pub fn wcharToUtf8(src_bytes: []const u8, out: []u8) ?[]const u8 {
    var units: [256]u16 = undefined;
    const max_units = @min(src_bytes.len / 2, units.len);
    var len: usize = 0;
    while (len < max_units) : (len += 1) {
        const cu = std.mem.readInt(u16, src_bytes[len * 2 ..][0..2], .little);
        if (cu == 0) break;
        units[len] = cu;
    }
    return utf16ZToUtf8(units[0..len], out);
}

/// Decode a UTF-16LE struct field into `out` as UTF-8.
pub fn wstringFieldUtf8(comptime field: []const u8, self: anytype, out: []u8) ?[]const u8 {
    const value = @field(self, field);
    return wcharToUtf8(std.mem.asBytes(&value), out);
}

test "cString trims at the NUL terminator" {
    const buf = [_]u8{ 'S', 'p', 'a', 0, 'X' };
    try std.testing.expectEqualStrings("Spa", cString(&buf));
}

test "cstr helpers stop at NUL and validate UTF-8" {
    const src = [_]u8{ 'S', 'p', 'a', 0, 'X' };
    try std.testing.expectEqualStrings("Spa", cstr(&src));
    var out: [16]u8 = undefined;
    try std.testing.expectEqualStrings("Spa", cstrToUtf8(&src, &out).?);
}

test "utf16ZToUtf8 decodes a code-unit slice and stops at NUL" {
    const wide = [_]u16{ 'a', 'c', 's', '.', 'e', 'x', 'e', 0, 'X' };
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("acs.exe", utf16ZToUtf8(&wide, &out).?);
}

test "wcharToUtf8 decodes a UTF-16LE name and stops at NUL" {
    const src = [_]u8{ 'M', 0, 'o', 0, 'n', 0, 'z', 0, 'a', 0, 0, 0, 'X', 0 };
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Monza", wcharToUtf8(&src, &out).?);
}

test "wstringFieldUtf8 decodes UTF-16LE struct fields" {
    const Sample = extern struct {
        name: [33]u16 = @splat(0),
    };

    var sample: Sample = .{};
    const car = std.unicode.utf8ToUtf16LeStringLiteral("Ferrari 458");
    @memcpy(sample.name[0..car.len], car);

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ferrari 458", wstringFieldUtf8("name", &sample, &out).?);
}
