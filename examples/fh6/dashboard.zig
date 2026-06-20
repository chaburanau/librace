//! Forza Horizon 6 dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const fh6 = librace.simulators.fh6;

pub const title = "Forza Horizon 6 | librace";

const rad_to_deg: f64 = 180.0 / std.math.pi;
const steer_to_deg: f64 = 900.0 / 127.0;

/// Allow time to alt-tab into FH6 and start driving before giving up.
const connect_timeout_ms: u32 = 120_000;

pub const Context = struct {
    client: ?fh6.Client = null,
    header_right_buf: [64]u8 = undefined,
    car_buf: [64]u8 = undefined,
    discovery_buf: [64]u8 = undefined,
};

pub fn connect(ctx: *Context) !void {
    ctx.client = try fh6.waitForConnection(std.heap.page_allocator, connect_timeout_ms);
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

pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.AddressInUse => try w.print(
            "UDP port {d} is already in use — close other apps (SimHub, another dashboard, zig build run-fh6).\n",
            .{fh6.default_port},
        ),
        error.Timeout => try w.print(
            "No packets on port {d} within {d}s — enable Data Out, set IP 127.0.0.1 port {d}, then drive.\n",
            .{ fh6.default_port, connect_timeout_ms / 1000, fh6.default_port },
        ),
        else => try w.print(
            "Settings → HUD and Gameplay → Data Out: On, IP 127.0.0.1, port {d}.\n",
            .{fh6.default_port},
        ),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const p = c.packet();

    data.header_left = p.sessionLabel();
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} ts={d} pos={d}", .{
        c.fieldCount(),
        p.timestamp_ms,
        p.race_position,
    }) catch "?";

    data.track = if (p.is_race_on != 0) "horizon" else "idle";
    data.car = p.formatCarSummary(&ctx.car_buf);
    data.driver = "?";
    data.session_type = p.drivetrainValue().label();
    data.track_length = "?";
    data.on_track = if (p.is_race_on != 0) "driving" else "idle";

    data.speed_kmh = @floatCast(p.speedKmh());
    data.gear = @floatFromInt(p.displayGear());
    data.rpm = p.current_engine_rpm;
    data.lap = @floatFromInt(p.lap_number);
    data.lap_cur = p.current_lap;
    data.lap_best = p.best_lap;
    data.lap_last = p.last_lap;
    data.fuel = p.fuel;
    data.fuel_h = 0;

    data.throttle_pct = @as(f64, p.accel) / 255.0 * 100.0;
    data.brake_pct = @as(f64, p.brake) / 255.0 * 100.0;
    data.clutch_pct = @as(f64, p.clutch) / 255.0 * 100.0;
    data.steering_deg = @as(f64, p.steer) * steer_to_deg;

    data.lat_g = p.acceleration_z / 9.81;
    data.long_g = p.acceleration_x / 9.81;
    data.vert_g = p.acceleration_y / 9.81;
    data.yaw = @as(f64, p.yaw) * rad_to_deg;
    data.pitch = @as(f64, p.pitch) * rad_to_deg;
    data.roll = @as(f64, p.roll) * rad_to_deg;

    data.session_state = @floatFromInt(p.is_race_on);
    data.session_time = p.current_race_time;
    data.session_num = @floatFromInt(p.race_position);

    data.var_count = c.fieldCount();
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "ordinal={d} class={s} pi={d}", .{
        p.car_ordinal,
        p.carClassValue().label(),
        p.car_performance_index,
    }) catch "?";
}
