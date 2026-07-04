/// Number of fields on a struct type.
pub fn structFieldCount(comptime T: type) usize {
    return @typeInfo(T).@"struct".fields.len;
}

/// Sum of `structFieldCount` across several struct types.
pub fn sumStructFieldCounts(comptime types: []const type) usize {
    var total: usize = 0;
    inline for (types) |T| {
        total += structFieldCount(T);
    }
    return total;
}

const std = @import("std");

test "structFieldCount and sumStructFieldCounts" {
    const A = struct { x: i32, y: f32 };
    const B = struct { z: u8 };
    try std.testing.expectEqual(@as(usize, 2), structFieldCount(A));
    try std.testing.expectEqual(@as(usize, 1), structFieldCount(B));
    try std.testing.expectEqual(@as(usize, 3), sumStructFieldCounts(&.{ A, B }));
}
