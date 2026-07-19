const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const ace = librace.simulators.ace;
const simple = example_common.simple;

const Context = struct {
    client: ?ace.Client = null,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try ace.connect(std.heap.page_allocator, io, .{});
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
        return ace.field_count;
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const c = &ctx.client.?;
        const p = c.physics();
        const g = c.graphics();
        const st = c.static();

        sample.track = nonEmpty(if (st) |s| s.trackName() else null);
        sample.car = nonEmpty(g.carModel());
        sample.gear = p.gear;
        sample.speed_kmh = p.speed_kmh;
        sample.rpm = @floatFromInt(p.rpms);
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.NotFound => try w.print("Shared memory not found — is Assetto Corsa Evo running and in a session?\n", .{}),
            error.MapFailed => try w.print("Shared memory found but could not be mapped.\n", .{}),
            error.InvalidData => try w.print("Shared memory mapped but the page was smaller than expected.\n", .{}),
            error.UnsupportedPlatform => try w.print("AC Evo telemetry is only supported on Windows.\n", .{}),
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
        .simulator_name = ace.name,
        .transport = @tagName(ace.transport),
        .short_name = "ace",
    }, &ctx, Context);
    try simple.finish(result);
}
