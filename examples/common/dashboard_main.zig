const std = @import("std");
const build_options = @import("build_options");
const example_common = @import("example_common");

const dash = example_common.dashboard;

pub fn main(init: std.process.Init) !void {
    if (comptime !build_options.implemented) {
        return dash.failNotImplemented(init.io, build_options.short_name);
    } else {
        const sim = @import("sim");
        var ctx: sim.Context = .{};
        try dash.run(init.io, .{
            .title = sim.title,
            .refresh_ms = 100,
            .columns = 4,
        }, &ctx, sim);
    }
}
