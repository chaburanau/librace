const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const lmu = librace.simulators.lmu;
const simple = example_common.simple;

const Context = struct {
    client: ?lmu.Client = null,
    track_buf: [96]u8 = undefined,
    car_buf: [96]u8 = undefined,

    pub fn connect(ctx: *Context, _: std.Io) !void {
        ctx.client = try lmu.connect(std.heap.page_allocator);
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
        return ctx.client.?.fieldCount();
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const c = &ctx.client.?;
        const t = c.telemetry();

        sample.track = nonEmpty(c.getString(lmu.keys.session.track_name, &ctx.track_buf));
        sample.car = nonEmpty(c.getString(lmu.keys.telem.vehicle_name, &ctx.car_buf));
        sample.gear = t.gear;
        sample.speed_kmh = @floatCast(t.speedKmh());
        sample.rpm = @floatCast(t.engine_rpm);
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.NotFound => try w.print("LMU shared memory not found - is Le Mans Ultimate running with Enable Plugins on?\n", .{}),
            error.MapFailed => try w.print("LMU shared memory found but could not be mapped.\n", .{}),
            error.InvalidData => try w.print("LMU shared memory mapped but the page was smaller than expected.\n", .{}),
            error.UnsupportedPlatform => try w.print("LMU native telemetry is only supported on Windows.\n", .{}),
            else => try w.print("Enter a live session before running the example.\n", .{}),
        }
    }
};

fn nonEmpty(value: ?[]const u8) []const u8 {
    const s = value orelse return "?";
    return if (s.len > 0) s else "?";
}

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = lmu.name,
        .transport = @tagName(lmu.transport),
        .short_name = "lmu",
    }, &ctx, Context);
    try simple.finish(result);
}
