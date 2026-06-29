//! iRacing dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;
const connect_error = @import("iracing_connect");

const ir = librace.simulators.iracing;

pub const title = "iRacing | librace";

/// Telemetry fields bound by name to IRSDK variables (see `Client.bind`). Field names must
/// match IRSDK variable names exactly; the binding fills these each frame.
const Telemetry = struct {
    Speed: f32 = 0,
    RPM: f32 = 0,
    Gear: i32 = 0,
    Throttle: f32 = 0,
    Brake: f32 = 0,
    Clutch: f32 = 0,
    SteeringWheelAngle: f32 = 0,
    Lap: i32 = 0,
    LapCurrentLapTime: f32 = 0,
    LapBestLapTime: f32 = 0,
    LapLastLapTime: f32 = 0,
    FuelLevel: f32 = 0,
    FuelUsePerHour: f32 = 0,
    LatAccel: f32 = 0,
    LongAccel: f32 = 0,
    VertAccel: f32 = 0,
    Yaw: f32 = 0,
    Pitch: f32 = 0,
    Roll: f32 = 0,
    SessionState: i32 = 0,
    SessionTime: f64 = 0,
    SessionNum: i32 = 0,
    IsOnTrack: bool = false,
};

pub const Context = struct {
    client: ?ir.Client = null,
    telemetry: ?ir.Binding(Telemetry) = null,
    header_right_buf: [48]u8 = undefined,
    discovery_buf: [48]u8 = undefined,
};

pub fn connect(ctx: *Context, _: std.Io) !void {
    ctx.client = try ir.connect(std.heap.page_allocator);
}

pub fn deinit(ctx: *Context) void {
    if (ctx.client) |*c| c.deinit();
    ctx.client = null;
    ctx.telemetry = null;
}

pub fn isConnected(ctx: *Context) bool {
    return ctx.client.?.isConnected();
}

pub fn poll(ctx: *Context) bool {
    return ctx.client.?.poll().isOk();
}

pub fn connectErrorHint(ctx: *Context, err: anyerror, w: *std.Io.Writer) !void {
    try connect_error.printConnectError(ctx, err, w);
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const c = &ctx.client.?;
    const keys = ir.keys;

    data.header_left = "live";

    const session_update = c.sessionInfoUpdate() orelse -1;
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "vars={d} sess#{d}", .{
        c.varCount(),
        session_update,
    }) catch "?";

    // Session metadata: cached path lookups + player-correct driver/car via DriverCarIdx.
    data.track = c.sessionGet(keys.session.track_display_name) orelse
        c.sessionGet(keys.session.track_name) orelse "?";
    data.car = c.playerDriverGet(keys.driver.car_screen_name) orelse
        c.playerDriverGet(keys.driver.car_path) orelse "?";
    data.driver = c.playerDriverGet(keys.driver.user_name) orelse "?";
    data.session_type = c.sessionGet(keys.session.session_type) orelse "?";
    data.track_length = c.sessionGet(keys.session.track_length_official) orelse "?";

    // Telemetry: bind once (resolves handles lazily), then read typed fields each frame.
    if (ctx.telemetry == null) ctx.telemetry = c.bind(Telemetry);
    var t = &ctx.telemetry.?;
    t.update();
    const v = t.values;

    data.on_track = if (v.IsOnTrack) "yes" else "no";

    data.speed_kmh = @as(f64, v.Speed) * 3.6;
    data.gear = @floatFromInt(v.Gear);
    data.rpm = v.RPM;
    data.lap = @floatFromInt(v.Lap);
    data.lap_cur = v.LapCurrentLapTime;
    data.lap_best = v.LapBestLapTime;
    data.lap_last = v.LapLastLapTime;
    data.fuel = v.FuelLevel;
    data.fuel_h = v.FuelUsePerHour;

    data.throttle_pct = @as(f64, v.Throttle) * 100;
    data.brake_pct = @as(f64, v.Brake) * 100;
    data.clutch_pct = @as(f64, v.Clutch) * 100;
    data.steering_deg = v.SteeringWheelAngle;

    data.lat_g = @as(f64, v.LatAccel) / 9.81;
    data.long_g = @as(f64, v.LongAccel) / 9.81;
    data.vert_g = @as(f64, v.VertAccel) / 9.81;
    data.yaw = v.Yaw;
    data.pitch = v.Pitch;
    data.roll = v.Roll;

    data.session_state = @floatFromInt(v.SessionState);
    data.session_time = v.SessionTime;
    data.session_num = @floatFromInt(v.SessionNum);

    data.var_count = c.varCount();
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "vars={d} yaml=6", .{data.var_count}) catch "?";
}
