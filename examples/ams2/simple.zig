const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const ams2 = librace.simulators.ams2;
const simple = example_common.simple;

const Context = struct {
    client: ?ams2.Client = null,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try ams2.connect(std.heap.page_allocator, io, .{});
    }

    pub fn deinit(ctx: *Context, _: std.Io) void {
        if (ctx.client) |*c| c.deinit();
        ctx.client = null;
    }

    pub fn isConnected(ctx: *Context) bool {
        return ctx.client.?.isConnected();
    }

    pub fn poll(ctx: *Context, _: std.Io) bool {
        return ctx.client.?.poll().isOk();
    }

    pub fn varCount(_: *Context) usize {
        return ams2.field_count;
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const s = ctx.client.?.shared();
        sample.track = nonEmpty(s.trackLocation());
        sample.car = nonEmpty(s.carName());
        sample.gear = s.displayGear();
        sample.speed_kmh = s.speedKmh();
        sample.rpm = s.rpm;
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.NotFound => try w.print("AMS2 shared memory ($pcars2$) not found - is Automobilista 2 running with Shared Memory set to Project CARS 2?\n", .{}),
            error.MapFailed => try w.print("AMS2 shared memory found but could not be mapped at the required size.\n", .{}),
            error.VersionMismatch => try w.print("AMS2 shared memory version mismatch (expected {d}).\n", .{ams2.shared_memory_version}),
            error.UnsupportedPlatform => try w.print("AMS2 telemetry is only supported on Windows.\n", .{}),
            else => try w.print("Enter a live session before running the example.\n", .{}),
        }
    }
};

fn nonEmpty(value: []const u8) []const u8 {
    return if (value.len > 0) value else "?";
}

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = ams2.name,
        .transport = @tagName(ams2.transport),
        .short_name = "ams2",
    }, &ctx, Context);
    try simple.finish(result);
}
