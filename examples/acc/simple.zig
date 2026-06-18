const std = @import("std");
const example_common = @import("example_common");

const simple = example_common.simple;

pub fn main(init: std.process.Init) !void {
    const result = try simple.failNotImplemented(init.io, "acc");
    try simple.finish(result);
}
