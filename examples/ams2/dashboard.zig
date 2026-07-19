//! Automobilista 2 dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const ams2 = librace.simulators.ams2;

pub const title = "Automobilista 2 | librace";

const rad_to_deg: f64 = 180.0 / std.math.pi;
const ms2_per_g: f64 = 9.80665;

pub const Context = struct {
    client: ?ams2.Client = null,
    header_right_buf: [96]u8 = undefined,
    track_buf: [96]u8 = undefined,
    track_len_buf: [32]u8 = undefined,
    discovery_buf: [96]u8 = undefined,
};

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

pub fn connectErrorHint(_: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.NotFound => try w.print("AMS2 shared memory ($pcars2$) not found - is Automobilista 2 running with Shared Memory set to Project CARS 2?\n", .{}),
        error.VersionMismatch => try w.print("AMS2 shared memory version mismatch (expected {d}).\n", .{ams2.shared_memory_version}),
        error.UnsupportedPlatform => try w.print("AMS2 telemetry is only supported on Windows.\n", .{}),
        else => try w.print("Enter a live session before running the dashboard.\n", .{}),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const s = c.shared();

    data.header_left = s.gameStateValue().label();
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} cars={d} v={d}", .{
        ams2.field_count,
        @max(s.num_participants, 0),
        s.version,
    }) catch "?";

    data.track = formatTrack(ctx, s);
    data.car = nonEmpty(s.carName());
    data.driver = nonEmpty(s.playerName());
    data.session_type = s.sessionStateValue().label();
    data.track_length = formatTrackLength(ctx, s);
    data.on_track = s.pitModeValue().label();

    data.speed_kmh = s.speedKmh();
    data.gear = @floatFromInt(s.displayGear());
    data.rpm = s.rpm;
    if (s.viewedParticipant()) |p| {
        data.lap = @floatFromInt(p.current_lap);
    } else {
        data.lap = 0;
    }
    data.lap_cur = s.current_time;
    data.lap_best = s.best_lap_time;
    data.lap_last = s.last_lap_time;
    data.fuel = s.fuel_level * s.fuel_capacity;
    data.fuel_h = s.fuel_level * 100.0;

    data.throttle_pct = @max(0, s.throttle) * 100.0;
    data.brake_pct = @max(0, s.brake) * 100.0;
    data.clutch_pct = @max(0, s.clutch) * 100.0;
    data.steering_deg = s.steering * 180.0;

    data.lat_g = s.local_acceleration[0] / ms2_per_g;
    data.long_g = s.local_acceleration[2] / ms2_per_g;
    data.vert_g = s.local_acceleration[1] / ms2_per_g;
    data.yaw = s.orientation[1] * rad_to_deg;
    data.pitch = s.orientation[0] * rad_to_deg;
    data.roll = s.orientation[2] * rad_to_deg;

    data.session_state = @floatFromInt(s.race_state);
    data.session_time = if (s.event_time_remaining >= 0) s.event_time_remaining / 1000.0 else s.session_duration * 60.0;
    if (s.viewedParticipant()) |p| {
        data.session_num = @floatFromInt(p.race_position);
    } else {
        data.session_num = 0;
    }

    data.var_count = ams2.field_count;
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "fields={d} session={s} race={s}", .{
        ams2.field_count,
        s.sessionStateValue().label(),
        s.raceStateValue().label(),
    }) catch "?";
}

fn nonEmpty(value: []const u8) []const u8 {
    return if (value.len > 0) value else "?";
}

fn formatTrack(ctx: *Context, s: *const ams2.protocol.Shared) []const u8 {
    const track = s.trackLocation();
    const variation = s.trackVariation();
    if (track.len == 0) return "?";
    if (variation.len == 0) return track;
    return std.fmt.bufPrint(&ctx.track_buf, "{s} ({s})", .{ track, variation }) catch track;
}

fn formatTrackLength(ctx: *Context, s: *const ams2.protocol.Shared) []const u8 {
    if (s.track_length <= 0) return "?";
    return std.fmt.bufPrint(&ctx.track_len_buf, "{d:.0} m", .{s.track_length}) catch "?";
}
