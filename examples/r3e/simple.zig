const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const r3e = librace.simulators.r3e;
const simple = example_common.simple;

const Context = struct {
    client: ?r3e.Client = null,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try r3e.connect(std.heap.page_allocator, io, .{});
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
        return r3e.field_count;
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const s = ctx.client.?.shared();
        sample.track = nonEmpty(s.trackName());
        sample.car = nonEmpty(s.vehicle_info.nameUtf8());
        sample.gear = s.displayGear();
        sample.speed_kmh = s.speedKmh();
        sample.rpm = s.engineRpm();
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.NotFound => try w.print("RaceRoom shared memory ($R3E) not found - is RRRE.exe running in a session?\n", .{}),
            error.MapFailed => try w.print("RaceRoom shared memory found but could not be mapped at the required size.\n", .{}),
            error.VersionMismatch => try w.print("RaceRoom shared memory major version mismatch (expected {d}).\n", .{r3e.version_major}),
            error.UnsupportedPlatform => try w.print("RaceRoom telemetry is only supported on Windows.\n", .{}),
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
        .simulator_name = r3e.name,
        .transport = @tagName(r3e.transport),
        .short_name = "r3e",
    }, &ctx, Context);
    try simple.finish(result);
}
