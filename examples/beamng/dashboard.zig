//! BeamNG.drive dashboard data provider (OutGauge UDP).

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const beamng = librace.simulators.beamng;

pub const title = "BeamNG.drive | librace";

const poll_timeout: std.Io.Timeout = .{ .duration = .{
    .raw = std.Io.Duration.fromMilliseconds(500),
    .clock = .awake,
} };

pub const Context = struct {
    client: ?beamng.Client = null,
    header_right_buf: [96]u8 = undefined,
    discovery_buf: [96]u8 = undefined,
};

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

pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.AddressInUse => try w.print(
            "UDP port {d} is already in use — close other apps (SimHub, another dashboard, zig build run-beamng).\n",
            .{beamng.default_port},
        ),
        else => try w.print(
            "Options → Other → Protocols → OutGauge: On, IP 127.0.0.1, port {d}. Disable MotionSim on the same port.\n",
            .{beamng.default_port},
        ),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const p = ctx.client.?.packet();

    data.header_left = "outgauge";
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} id={d} flags=0x{x:0>4}", .{
        beamng.field_count,
        p.id,
        p.flags,
    }) catch "?";

    data.track = "outgauge";
    data.car = p.carName();
    data.driver = "?";
    data.session_type = if (p.prefersKm()) "metric" else "imperial";
    data.track_length = "?";
    data.on_track = "driving";

    data.speed_kmh = @floatCast(p.speedKmh());
    data.gear = @floatFromInt(p.displayGear());
    data.rpm = p.rpm;
    data.lap = 0;
    data.lap_cur = 0;
    data.lap_best = 0;
    data.lap_last = 0;
    data.fuel = p.fuel;
    data.fuel_h = 0;

    data.throttle_pct = @as(f64, p.throttle) * 100.0;
    data.brake_pct = @as(f64, p.brake) * 100.0;
    data.clutch_pct = @as(f64, p.clutch) * 100.0;
    data.steering_deg = 0;

    data.lat_g = 0;
    data.long_g = 0;
    data.vert_g = 0;
    data.yaw = 0;
    data.pitch = 0;
    data.roll = 0;

    data.session_state = 1;
    data.session_time = 0;
    data.session_num = 0;

    data.var_count = beamng.field_count;
    data.discovery_hint = std.fmt.bufPrint(
        &ctx.discovery_buf,
        "eng={d:.0}C oil={d:.0}C turbo={d:.2} lights=0x{x:0>3}",
        .{ p.eng_temp, p.oil_temp, p.turbo, p.show_lights },
    ) catch "?";
}
