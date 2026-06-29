const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const ir = librace.simulators.iracing;
const simple = example_common.simple;
const connect_error = @import("connect_error.zig");

const Context = struct {
    client: ?ir.Client = null,

    pub fn connect(ctx: *Context, _: std.Io) !void {
        ctx.client = try ir.connect(std.heap.page_allocator);
    }

    pub fn deinit(ctx: *Context) void {
        if (ctx.client) |*c| c.deinit();
        ctx.client = null;
    }

    pub fn isConnected(ctx: *Context) bool {
        return ctx.client.?.isConnected();
    }

    pub fn poll(ctx: *Context) bool {
        return ctx.client.?.poll().isOk();
    }

    pub fn varCount(ctx: *Context) usize {
        return ctx.client.?.varCount();
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const c = &ctx.client.?;
        const keys = ir.keys;

        sample.track = c.sessionGet(keys.session.track_display_name) orelse
            c.sessionGet(keys.session.track_name) orelse "?";
        sample.car = c.playerDriverGet(keys.driver.car_screen_name) orelse
            c.playerDriverGet(keys.driver.car_path) orelse "?";
        sample.gear = c.getAs(i32, keys.var_name.gear) catch 0;
        sample.speed_kmh = @as(f32, @floatCast(c.getNumber(keys.var_name.speed) orelse 0)) * 3.6;
        sample.rpm = @as(f32, @floatCast(c.getNumber(keys.var_name.rpm) orelse 0));
    }

    pub fn connectErrorHint(ctx: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try connect_error.printConnectError(ctx, err, w);
    }
};

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = ir.name,
        .transport = @tagName(ir.transport),
        .short_name = "iracing",
    }, &ctx, Context);
    try simple.finish(result);
}
