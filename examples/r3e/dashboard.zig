//! RaceRoom Racing Experience dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const r3e = librace.simulators.r3e;

pub const title = "RaceRoom Racing Experience | librace";

const rad_to_deg: f64 = 180.0 / std.math.pi;
const ms2_per_g: f64 = 9.80665;

pub const Context = struct {
    client: ?r3e.Client = null,
    header_right_buf: [96]u8 = undefined,
    track_buf: [96]u8 = undefined,
    track_len_buf: [32]u8 = undefined,
    discovery_buf: [96]u8 = undefined,
};

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

pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.NotFound => try w.print("RaceRoom shared memory ($R3E) not found - is RRRE.exe running in a session?\n", .{}),
        error.VersionMismatch => try w.print("RaceRoom shared memory major version mismatch (expected {d}).\n", .{r3e.version_major}),
        error.UnsupportedPlatform => try w.print("RaceRoom telemetry is only supported on Windows.\n", .{}),
        else => try w.print("Enter a live session before running the dashboard.\n", .{}),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const s = c.shared();

    data.header_left = s.sessionPhaseValue().label();
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} cars={d} v={d}.{d}", .{
        r3e.field_count,
        s.num_cars,
        s.version_major,
        s.version_minor,
    }) catch "?";

    data.track = formatTrack(ctx, s);
    data.car = nonEmpty(s.vehicle_info.nameUtf8());
    data.driver = nonEmpty(s.playerName());
    data.session_type = s.sessionTypeValue().label();
    data.track_length = formatTrackLength(ctx, s);
    data.on_track = if (s.in_pitlane == 1) "Pit Lane" else if (s.game_player_in_garage == 1) "Garage" else "Track";

    data.speed_kmh = s.speedKmh();
    data.gear = @floatFromInt(s.displayGear());
    data.rpm = s.engineRpm();
    data.lap = @floatFromInt(s.completed_laps);
    data.lap_cur = s.lap_time_current_self;
    data.lap_best = s.lap_time_best_self;
    data.lap_last = s.lap_time_previous_self;
    data.fuel = s.fuel_left;
    if (s.fuel_capacity > 0) {
        data.fuel_h = (s.fuel_left / s.fuel_capacity) * 100.0;
    } else {
        data.fuel_h = 0;
    }

    data.throttle_pct = @max(0, s.throttle) * 100.0;
    data.brake_pct = @max(0, s.brake) * 100.0;
    data.clutch_pct = @max(0, s.clutch) * 100.0;
    data.steering_deg = s.steer_input_raw * @as(f32, @floatFromInt(if (s.steer_lock_degrees > 0) s.steer_lock_degrees else 1));

    data.lat_g = s.local_acceleration.x / ms2_per_g;
    data.long_g = -s.local_acceleration.z / ms2_per_g;
    data.vert_g = s.local_acceleration.y / ms2_per_g;
    data.yaw = s.car_orientation.yaw * rad_to_deg;
    data.pitch = s.car_orientation.pitch * rad_to_deg;
    data.roll = s.car_orientation.roll * rad_to_deg;

    data.session_state = @floatFromInt(s.session_phase);
    data.session_time = if (s.session_time_remaining >= 0) s.session_time_remaining else s.session_time_duration;
    data.session_num = @floatFromInt(s.position);

    data.var_count = r3e.field_count;
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "fields={d} mode={s} phase={s}", .{
        r3e.field_count,
        s.gameModeValue().label(),
        s.sessionPhaseValue().label(),
    }) catch "?";
}

fn nonEmpty(value: []const u8) []const u8 {
    return if (value.len > 0) value else "?";
}

fn formatTrack(ctx: *Context, s: *const r3e.protocol.Shared) []const u8 {
    const track = s.trackName();
    const layout = s.layoutName();
    if (track.len == 0) return "?";
    if (layout.len == 0) return track;
    return std.fmt.bufPrint(&ctx.track_buf, "{s} ({s})", .{ track, layout }) catch track;
}

fn formatTrackLength(ctx: *Context, s: *const r3e.protocol.Shared) []const u8 {
    if (s.layout_length <= 0) return "?";
    return std.fmt.bufPrint(&ctx.track_len_buf, "{d:.0} m", .{s.layout_length}) catch "?";
}
