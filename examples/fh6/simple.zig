const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const fh6 = librace.simulators.fh6;
const simple = example_common.simple;

const Context = struct {
    client: ?fh6.Client = null,
    car_buf: [64]u8 = undefined,

    pub fn connect(ctx: *Context) !void {
        ctx.client = try fh6.waitForConnection(std.heap.page_allocator, 30_000);
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
        const p = c.packet();

        sample.track = p.sessionLabel();
        sample.car = p.formatCarSummary(&ctx.car_buf);
        sample.gear = p.displayGear();
        sample.speed_kmh = p.speedKmh();
        sample.rpm = p.current_engine_rpm;
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.AddressInUse => try w.print(
                "UDP port {d} is already in use — close other telemetry apps using this port.\n",
                .{fh6.default_port},
            ),
            error.Timeout => try w.print(
                "No FH6 Data Out packets received on port {d} within 30s.\n",
                .{fh6.default_port},
            ),
            else => try w.print(
                "Enable Data Out in FH6 (Settings → HUD and Gameplay), set IP to 127.0.0.1 and port to {d}, then drive.\n",
                .{fh6.default_port},
            ),
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = fh6.name,
        .transport = @tagName(fh6.transport),
        .short_name = "fh6",
    }, &ctx, Context);
    try simple.finish(result);
}
