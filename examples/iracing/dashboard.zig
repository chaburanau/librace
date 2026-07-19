//! iRacing dashboard data provider.

const std = @import("std");
const librace = @import("librace");
const dashboard = @import("example_common").dashboard;
const connect_error = @import("iracing_connect");

const ir = librace.simulators.iracing;

pub const title = "iRacing | librace";

const Indices = struct {
    speed: ?ir.Variable = null,
    rpm: ?ir.Variable = null,
    gear: ?ir.Variable = null,
    throttle: ?ir.Variable = null,
    brake: ?ir.Variable = null,
    clutch: ?ir.Variable = null,
    steering: ?ir.Variable = null,
    lap: ?ir.Variable = null,
    lap_current: ?ir.Variable = null,
    lap_best: ?ir.Variable = null,
    lap_last: ?ir.Variable = null,
    fuel: ?ir.Variable = null,
    fuel_per_hour: ?ir.Variable = null,
    lat_accel: ?ir.Variable = null,
    long_accel: ?ir.Variable = null,
    vert_accel: ?ir.Variable = null,
    yaw: ?ir.Variable = null,
    pitch: ?ir.Variable = null,
    roll: ?ir.Variable = null,
    session_state: ?ir.Variable = null,
    session_time: ?ir.Variable = null,
    session_num: ?ir.Variable = null,
    is_on_track: ?ir.Variable = null,
};

pub const Context = struct {
    client: ?ir.Client = null,
    session_snapshot: ?ir.SessionSnapshot = null,
    indices: Indices = .{},
    variables_version: u64 = 0,
    last_poll: ir.PollStatus = .stale,
    header_right_buf: [48]u8 = undefined,
    discovery_buf: [48]u8 = undefined,
    track_buf: [128]u8 = undefined,
    car_buf: [128]u8 = undefined,
    driver_buf: [128]u8 = undefined,
    session_type_buf: [64]u8 = undefined,
    track_length_buf: [64]u8 = undefined,
};

pub fn connect(ctx: *Context, io: std.Io) !void {
    ctx.client = try ir.connect(std.heap.page_allocator, io, .{});
}

pub fn deinit(ctx: *Context, _: std.Io) void {
    if (ctx.session_snapshot) |*snapshot| snapshot.deinit();
    if (ctx.client) |*client| client.deinit();
    ctx.* = .{};
}

pub fn isConnected(ctx: *Context) bool {
    return ctx.client.?.isConnected();
}

pub fn poll(ctx: *Context, _: std.Io) bool {
    ctx.last_poll = ctx.client.?.poll();
    if (!ctx.last_poll.isOk()) return false;
    refreshSnapshots(ctx) catch {
        ctx.last_poll = .rebuild_failed;
        return false;
    };
    return true;
}

pub fn connectErrorHint(ctx: *Context, err: anyerror, writer: *std.Io.Writer) !void {
    try connect_error.printConnectError(ctx, err, writer);
}

pub fn fillData(ctx: *Context, data: *dashboard.Data) void {
    const client = &ctx.client.?;
    const variables = client.variables();

    data.header_left = @tagName(ctx.last_poll);
    if (!ctx.last_poll.isOk()) return;

    const session_version = client.session().version() orelse -1;
    data.header_right = std.fmt.bufPrint(&ctx.header_right_buf, "vars={d} sess#{d}", .{
        client.header().variablesLen(),
        session_version,
    }) catch "?";

    if (ctx.session_snapshot) |*session| {
        data.track = sessionString(session, ir.keys.session.weekend_info, ir.keys.session.track_display_name, &ctx.track_buf) orelse
            sessionString(session, ir.keys.session.weekend_info, ir.keys.session.track_name, &ctx.track_buf) orelse "?";
        data.car = playerDriverString(session, ir.keys.driver.car_screen_name, &ctx.car_buf) orelse
            playerDriverString(session, ir.keys.driver.car_path, &ctx.car_buf) orelse "?";
        data.driver = playerDriverString(session, ir.keys.driver.user_name, &ctx.driver_buf) orelse "?";
        data.session_type = sessionString(session, ir.keys.session.weekend_info, ir.keys.session.session_type, &ctx.session_type_buf) orelse "?";
        data.track_length = sessionString(session, ir.keys.session.weekend_info, ir.keys.session.track_length_official, &ctx.track_length_buf) orelse "?";
    }

    data.on_track = if (readBool(variables, ctx.indices.is_on_track) orelse false) "yes" else "no";
    data.speed_kmh = (readFloat(variables, ctx.indices.speed) orelse 0) * 3.6;
    data.gear = @floatFromInt(readInt(variables, ctx.indices.gear) orelse 0);
    data.rpm = readFloat(variables, ctx.indices.rpm) orelse 0;
    data.lap = @floatFromInt(readInt(variables, ctx.indices.lap) orelse 0);
    data.lap_cur = readFloat(variables, ctx.indices.lap_current) orelse 0;
    data.lap_best = readFloat(variables, ctx.indices.lap_best) orelse 0;
    data.lap_last = readFloat(variables, ctx.indices.lap_last) orelse 0;
    data.fuel = readFloat(variables, ctx.indices.fuel) orelse 0;
    data.fuel_h = readFloat(variables, ctx.indices.fuel_per_hour) orelse 0;

    data.throttle_pct = (readFloat(variables, ctx.indices.throttle) orelse 0) * 100;
    data.brake_pct = (readFloat(variables, ctx.indices.brake) orelse 0) * 100;
    data.clutch_pct = (readFloat(variables, ctx.indices.clutch) orelse 0) * 100;
    data.steering_deg = readFloat(variables, ctx.indices.steering) orelse 0;

    data.lat_g = (readFloat(variables, ctx.indices.lat_accel) orelse 0) / 9.81;
    data.long_g = (readFloat(variables, ctx.indices.long_accel) orelse 0) / 9.81;
    data.vert_g = (readFloat(variables, ctx.indices.vert_accel) orelse 0) / 9.81;
    data.yaw = readFloat(variables, ctx.indices.yaw) orelse 0;
    data.pitch = readFloat(variables, ctx.indices.pitch) orelse 0;
    data.roll = readFloat(variables, ctx.indices.roll) orelse 0;

    data.session_state = @floatFromInt(readInt(variables, ctx.indices.session_state) orelse 0);
    data.session_time = readFloat(variables, ctx.indices.session_time) orelse 0;
    data.session_num = @floatFromInt(readInt(variables, ctx.indices.session_num) orelse 0);

    data.var_count = client.header().variablesLen();
    data.discovery_hint = std.fmt.bufPrint(&ctx.discovery_buf, "vars={d} tree=lazy", .{data.var_count}) catch "?";
}

fn refreshSnapshots(ctx: *Context) !void {
    const client = &ctx.client.?;
    const variables = client.variables();
    if (ctx.variables_version != variables.version()) {
        const names = ir.keys.var_name;
        ctx.indices = .{
            .speed = try variables.find(names.speed),
            .rpm = try variables.find(names.rpm),
            .gear = try variables.find(names.gear),
            .throttle = try variables.find(names.throttle),
            .brake = try variables.find(names.brake),
            .clutch = try variables.find(names.clutch),
            .steering = try variables.find(names.steering_wheel_angle),
            .lap = try variables.find(names.lap),
            .lap_current = try variables.find(names.lap_current_lap_time),
            .lap_best = try variables.find(names.lap_best_lap_time),
            .lap_last = try variables.find(names.lap_last_lap_time),
            .fuel = try variables.find(names.fuel_level),
            .fuel_per_hour = try variables.find(names.fuel_use_per_hour),
            .lat_accel = try variables.find(names.lat_accel),
            .long_accel = try variables.find(names.long_accel),
            .vert_accel = try variables.find(names.vert_accel),
            .yaw = try variables.find(names.yaw),
            .pitch = try variables.find(names.pitch),
            .roll = try variables.find(names.roll),
            .session_state = try variables.find(names.session_state),
            .session_time = try variables.find(names.session_time),
            .session_num = try variables.find(names.session_num),
            .is_on_track = try variables.find(names.is_on_track),
        };
        ctx.variables_version = variables.version();
    }

    const session_version = client.session().version() orelse return;
    if (ctx.session_snapshot == null or ctx.session_snapshot.?.version != session_version) {
        var replacement = try client.session().snapshot();
        errdefer replacement.deinit();
        if (ctx.session_snapshot) |*snapshot| snapshot.deinit();
        ctx.session_snapshot = replacement;
    }
}

fn readInt(variables: ir.VariablesView, index: ?ir.Variable) ?i32 {
    const value = variables.value(index orelse return null) catch return null;
    return value.asInt();
}

fn readFloat(variables: ir.VariablesView, index: ?ir.Variable) ?f64 {
    const value = variables.value(index orelse return null) catch return null;
    return value.asFloat();
}

fn readBool(variables: ir.VariablesView, index: ?ir.Variable) ?bool {
    const value = variables.value(index orelse return null) catch return null;
    return value.asBool();
}

fn sessionString(
    snapshot: *const ir.SessionSnapshot,
    section: []const u8,
    key: []const u8,
    buffer: []u8,
) ?[]const u8 {
    const scalar = (snapshot.query(&.{
        .{ .key = section },
        .{ .key = key },
    }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}

fn playerDriverString(snapshot: *const ir.SessionSnapshot, key: []const u8, buffer: []u8) ?[]const u8 {
    const player = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.driver_car_idx },
    }) catch return null) orelse return null;
    const player_index = player.asInt() catch return null;
    const scalar = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.drivers },
        .{ .select = .{
            .key = ir.keys.driver.car_idx,
            .value = .{ .int = player_index },
        } },
        .{ .key = key },
    }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}
