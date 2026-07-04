//! Assetto Corsa dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;

const ac = librace.simulators.ac;

pub const title = "Assetto Corsa | librace";

const rad_to_deg: f64 = 180.0 / std.math.pi;

pub const Context = struct {
    client: ?ac.Client = null,
    header_right_buf: [48]u8 = undefined,
    track_buf: [96]u8 = undefined,
    car_buf: [96]u8 = undefined,
    driver_buf: [96]u8 = undefined,
    name_buf: [48]u8 = undefined,
    surname_buf: [48]u8 = undefined,
    track_len_buf: [24]u8 = undefined,
    discovery_buf: [48]u8 = undefined,
};

pub fn connect(ctx: *Context, io: std.Io) !void {
    ctx.client = try ac.connect(std.heap.page_allocator, io, .{});
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
        error.NotFound => try w.print("Shared memory not found — is Assetto Corsa running and in a session?\n", .{}),
        error.UnsupportedPlatform => try w.print("Assetto Corsa telemetry is only supported on Windows.\n", .{}),
        else => try w.print("Enter a live session before running the dashboard.\n", .{}),
    }
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const p = c.physics();
    const g = c.graphics();
    const st = c.static();

    data.header_left = @tagName(c.liveStatus());
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "fields={d} pkt={d}", .{
        ac.field_count,
        c.livePhysicsPacketId(),
    }) catch "?";

    // Session metadata — wchar strings decoded into owned buffers.
    data.track = nonEmpty(if (st) |s| s.trackUtf8(&ctx.track_buf) else null);
    data.car = nonEmpty(if (st) |s| s.carModelUtf8(&ctx.car_buf) else null);
    data.driver = formatDriver(ctx, st);
    data.session_type = g.sessionValue().label();
    data.track_length = formatTrackLength(ctx, st);
    data.on_track = g.locationLabel();

    // Drive
    data.speed_kmh = p.speed_kmh;
    // AC gear encoding: 0 = reverse, 1 = neutral, 2+ = forward. Shift to display scale.
    data.gear = @as(f64, @floatFromInt(p.gear)) - 1;
    data.rpm = @floatFromInt(p.rpms);
    data.lap = @floatFromInt(g.completed_laps);
    data.lap_cur = @as(f64, @floatFromInt(g.i_current_time)) / 1000.0;
    data.lap_best = @as(f64, @floatFromInt(g.i_best_time)) / 1000.0;
    data.lap_last = @as(f64, @floatFromInt(g.i_last_time)) / 1000.0;
    data.fuel = p.fuel;

    // Inputs
    data.throttle_pct = @as(f64, p.gas) * 100;
    data.brake_pct = @as(f64, p.brake) * 100;
    data.clutch_pct = @as(f64, p.clutch) * 100;
    data.steering_deg = @as(f64, p.steer_angle);

    // Motion: accG is already in G; chassis orientation is in radians.
    data.lat_g = p.acc_g[0];
    data.long_g = p.acc_g[2];
    data.vert_g = p.acc_g[1];
    data.yaw = @as(f64, p.heading) * rad_to_deg;
    data.pitch = @as(f64, p.pitch) * rad_to_deg;
    data.roll = @as(f64, p.roll) * rad_to_deg;

    // Timing
    data.session_state = @floatFromInt(@intFromEnum(c.liveStatus()));
    data.session_time = @as(f64, g.session_time_left) / 1000.0;
    data.session_num = @floatFromInt(g.position);

    data.var_count = ac.field_count;
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "fields={d} pages=3", .{
        ac.field_count,
    }) catch "?";
}

fn nonEmpty(value: ?[]const u8) []const u8 {
    const s = value orelse return "?";
    return if (s.len > 0) s else "?";
}

fn formatDriver(ctx: *Context, st: ?*const ac.Static) []const u8 {
    const s = st orelse return "?";
    const first = s.playerNameUtf8(&ctx.name_buf) orelse "";
    const last = s.playerSurnameUtf8(&ctx.surname_buf) orelse "";
    if (first.len == 0 and last.len == 0) return "?";
    return std.fmt.bufPrint(&ctx.driver_buf, "{s} {s}", .{ first, last }) catch "?";
}

fn formatTrackLength(ctx: *Context, st: ?*const ac.Static) []const u8 {
    const s = st orelse return "?";
    return std.fmt.bufPrint(&ctx.track_len_buf, "{d:.0} m", .{s.track_spline_length}) catch "?";
}
