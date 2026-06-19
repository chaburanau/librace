//! Le Mans Ultimate dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const lmu = librace.simulators.lmu;

pub const title = "Le Mans Ultimate | librace";

const rad_to_deg: f64 = 180.0 / std.math.pi;
const ms2_per_g: f64 = 9.80665;

pub const Context = struct {
    client: ?lmu.Client = null,
    header_right_buf: [96]u8 = undefined,
    track_buf: [96]u8 = undefined,
    car_buf: [96]u8 = undefined,
    driver_buf: [96]u8 = undefined,
    track_len_buf: [32]u8 = undefined,
    discovery_buf: [96]u8 = undefined,
};

pub fn connect(ctx: *Context) !void {
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

pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.NotFound => try w.print("LMU shared memory not found - is Le Mans Ultimate running with Enable Plugins on?\n", .{}),
        error.UnsupportedPlatform => try w.print("LMU native telemetry is only supported on Windows.\n", .{}),
        else => try w.print("Enter a live session before running the dashboard.\n", .{}),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const t = c.telemetry();
    const s = c.session();
    const v = c.vehicle();

    data.header_left = s.gamePhaseValue().label();
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} cars={d} tc={d}/{d} abs={d}/{d}", .{
        c.fieldCount(),
        s.num_vehicles,
        t.tc,
        t.tc_max,
        t.abs,
        t.abs_max,
    }) catch "?";

    data.track = nonEmpty(c.getString(lmu.keys.session.track_name, &ctx.track_buf));
    data.car = nonEmpty(c.getString(lmu.keys.telem.vehicle_name, &ctx.car_buf));
    data.driver = nonEmpty(c.getString(lmu.keys.vehicle.driver_name, &ctx.driver_buf));
    data.session_type = s.sessionValue().label();
    data.track_length = formatTrackLength(ctx, s);
    data.on_track = v.pitStateValue().label();

    data.speed_kmh = t.speedKmh();
    data.gear = @floatFromInt(t.gear);
    data.rpm = t.engine_rpm;
    data.lap = @floatFromInt(v.total_laps);
    data.lap_cur = @max(0, s.current_et - v.lap_start_et);
    data.lap_best = v.best_lap_time;
    data.lap_last = v.last_lap_time;
    data.fuel = t.fuel;
    data.fuel_h = @as(f64, @floatFromInt(v.fuel_fraction)) / 255.0 * 100.0;

    data.throttle_pct = t.unfiltered_throttle * 100.0;
    data.brake_pct = t.unfiltered_brake * 100.0;
    data.clutch_pct = t.unfiltered_clutch * 100.0;
    data.steering_deg = t.unfiltered_steering * 100.0;

    data.lat_g = t.local_accel.x / ms2_per_g;
    data.long_g = -t.local_accel.z / ms2_per_g;
    data.vert_g = t.local_accel.y / ms2_per_g;
    const euler = matrixToEuler(t.ori);
    data.yaw = euler.yaw * rad_to_deg;
    data.pitch = euler.pitch * rad_to_deg;
    data.roll = euler.roll * rad_to_deg;

    data.session_state = @floatFromInt(@intFromEnum(s.game_phase));
    data.session_time = s.current_et;
    data.session_num = @floatFromInt(v.place);

    data.var_count = c.fieldCount();
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "fields={d} phase={s} grip={d} rain={d:.2}", .{
        c.fieldCount(),
        s.gamePhaseValue().label(),
        s.track_grip_level,
        s.raining,
    }) catch "?";
}

fn nonEmpty(value: ?[]const u8) []const u8 {
    const s = value orelse return "?";
    return if (s.len > 0) s else "?";
}

fn formatTrackLength(ctx: *Context, s: *const lmu.protocol.ScoringInfoV01) []const u8 {
    if (s.lap_dist <= 0) return "?";
    return std.fmt.bufPrint(&ctx.track_len_buf, "{d:.0} m", .{s.lap_dist}) catch "?";
}

const Euler = struct { yaw: f64, pitch: f64, roll: f64 };

fn matrixToEuler(ori: [3]lmu.protocol.TelemVect3) Euler {
    // LMU exposes orientation rows. This produces stable dashboard angles without changing
    // the SDK surface; consumers can still use the raw matrix for their preferred convention.
    return .{
        .yaw = std.math.atan2(ori[0].z, ori[2].z),
        .pitch = std.math.asin(std.math.clamp(-ori[1].z, -1.0, 1.0)),
        .roll = std.math.atan2(ori[1].x, ori[1].y),
    };
}
