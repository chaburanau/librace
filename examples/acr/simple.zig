const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const acr = librace.simulators.acr;
const simple = example_common.simple;

const Context = struct {
    client: ?acr.Client = null,
    track_buf: [96]u8 = undefined,
    car_buf: [96]u8 = undefined,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try acr.connect(std.heap.page_allocator, io, .{});
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
        return acr.field_count;
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const c = &ctx.client.?;
        const p = c.physics();
        const st = c.static();

        sample.track = nonEmpty(if (st) |s| s.trackUtf8(&ctx.track_buf) else null);
        sample.car = nonEmpty(if (st) |s| s.carModelUtf8(&ctx.car_buf) else null);
        sample.gear = p.gear;
        sample.speed_kmh = p.speed_kmh;
        sample.rpm = @floatFromInt(p.rpms);
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.NotFound => try w.print("Shared memory not found — is Assetto Corsa Rally running and in a stage?\n", .{}),
            error.MapFailed => try w.print("Shared memory found but could not be mapped.\n", .{}),
            error.InvalidData => try w.print("Shared memory mapped but the page was smaller than expected.\n", .{}),
            error.UnsupportedPlatform => try w.print("AC Rally telemetry is only supported on Windows.\n", .{}),
            else => try w.print("Enter a live stage before running the example.\n", .{}),
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
        .simulator_name = acr.name,
        .transport = @tagName(acr.transport),
        .short_name = "acr",
    }, &ctx, Context);
    try simple.finish(result);
}
