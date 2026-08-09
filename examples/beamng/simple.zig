const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const beamng = librace.simulators.beamng;
const simple = example_common.simple;
const poll_timeout: std.Io.Timeout = .{ .duration = .{
    .raw = std.Io.Duration.fromSeconds(30),
    .clock = .awake,
} };

const Context = struct {
    client: ?beamng.Client = null,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try beamng.connect(io, .{});
    }

    pub fn deinit(ctx: *Context, io: std.Io) void {
        if (ctx.client) |*c| c.deinit(io);
        ctx.client = null;
    }

    pub fn isConnected(ctx: *Context) bool {
        return ctx.client != null;
    }

    pub fn poll(ctx: *Context, io: std.Io) bool {
        return (ctx.client.?.poll(io, poll_timeout) catch return false).isOk();
    }

    pub fn varCount(_: *Context) usize {
        return beamng.field_count;
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const p = ctx.client.?.packet();

        sample.track = "outgauge";
        sample.car = p.carName();
        sample.gear = p.displayGear();
        sample.speed_kmh = p.speedKmh();
        sample.rpm = p.rpm;
    }

    pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
        try w.print("Connect failed: {s}\n", .{@errorName(err)});
        switch (err) {
            error.AddressInUse => try w.print(
                "UDP port {d} is already in use — close other telemetry apps using this port.\n",
                .{beamng.default_port},
            ),
            else => try w.print(
                "Enable OutGauge in BeamNG (Options → Other → Protocols), set IP to 127.0.0.1 and port to {d}, disable MotionSim on the same port, then drive.\n",
                .{beamng.default_port},
            ),
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = beamng.name,
        .transport = @tagName(beamng.transport),
        .short_name = "beamng",
    }, &ctx, Context);
    try simple.finish(result);
}
