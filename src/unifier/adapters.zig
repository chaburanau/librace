//! Explicit mappings from native simulator snapshots to the common subset.

const std = @import("std");
const detect = @import("../detect/root.zig");
const sims = @import("../simulators/root.zig");
const types = @import("types.zig");

const g: f32 = 9.80665;
const deg_to_rad: f32 = std.math.pi / 180.0;

const IracingIndices = struct {
    speed: ?sims.iracing.Variable = null,
    rpm: ?sims.iracing.Variable = null,
    gear: ?sims.iracing.Variable = null,
    throttle: ?sims.iracing.Variable = null,
    brake: ?sims.iracing.Variable = null,
    clutch: ?sims.iracing.Variable = null,
    steering: ?sims.iracing.Variable = null,
    lap: ?sims.iracing.Variable = null,
    lap_current: ?sims.iracing.Variable = null,
    lap_best: ?sims.iracing.Variable = null,
    lap_last: ?sims.iracing.Variable = null,
    fuel: ?sims.iracing.Variable = null,
    lat_accel: ?sims.iracing.Variable = null,
    long_accel: ?sims.iracing.Variable = null,
    vert_accel: ?sims.iracing.Variable = null,
    yaw: ?sims.iracing.Variable = null,
    pitch: ?sims.iracing.Variable = null,
    roll: ?sims.iracing.Variable = null,
    session_state: ?sims.iracing.Variable = null,
    session_time: ?sims.iracing.Variable = null,
};

pub const State = struct {
    allocator: std.mem.Allocator,
    data: types.Snapshot = .{ .simulator = .iracing, .pid = 0 },
    track_buf: [160]u8 = undefined,
    car_buf: [160]u8 = undefined,
    driver_buf: [160]u8 = undefined,
    track_len: usize = 0,
    car_len: usize = 0,
    driver_len: usize = 0,
    iracing_indices: IracingIndices = .{},
    iracing_variables_version: u64 = 0,
    iracing_session: ?sims.iracing.SessionSnapshot = null,
    iracing_session_kind: ?types.SessionKind = null,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        self.resetClient();
    }

    pub fn resetClient(self: *State) void {
        if (self.iracing_session) |*session_snapshot| session_snapshot.deinit();
        self.iracing_session = null;
        self.iracing_indices = .{};
        self.iracing_variables_version = 0;
        self.iracing_session_kind = null;
        self.clear();
    }

    fn clear(self: *State) void {
        self.clearData();
        self.track_len = 0;
        self.car_len = 0;
        self.driver_len = 0;
    }

    fn clearData(self: *State) void {
        self.data = .{ .simulator = .iracing, .pid = 0 };
    }

    pub fn snapshot(self: *const State, simulator: detect.Simulator, pid: u32) types.Snapshot {
        var result = self.data;
        result.simulator = simulator;
        result.pid = pid;
        result.identity = .{
            .track = if (self.track_len == 0) null else self.track_buf[0..self.track_len],
            .car = if (self.car_len == 0) null else self.car_buf[0..self.car_len],
            .driver = if (self.driver_len == 0) null else self.driver_buf[0..self.driver_len],
        };
        return result;
    }

    fn setTrack(self: *State, value: ?[]const u8) void {
        self.track_len = copyText(&self.track_buf, value);
    }

    fn setCar(self: *State, value: ?[]const u8) void {
        self.car_len = copyText(&self.car_buf, value);
    }

    fn setDriver(self: *State, value: ?[]const u8) void {
        self.driver_len = copyText(&self.driver_buf, value);
    }
};

pub fn normalizeAc(state: *State, client: *sims.ac.Client) bool {
    state.clear();
    const p = client.physics();
    const gr = client.graphics();
    if (client.static()) |s| {
        var track: [256]u8 = undefined;
        var car: [256]u8 = undefined;
        var first: [128]u8 = undefined;
        var last: [128]u8 = undefined;
        state.setTrack(s.trackUtf8(&track));
        state.setCar(s.carModelUtf8(&car));
        state.setDriver(joinName(&state.driver_buf, s.playerNameUtf8(&first), s.playerSurnameUtf8(&last)));
    }
    fillAcLike(state, p.speed_kmh, p.gear, p.rpms, p.fuel, p.gas, p.brake, p.clutch, p.acc_g, p.heading, p.pitch, p.roll);
    state.data.controls.steering_rad = p.steer_angle;
    state.data.lap = .{
        .number = nonNegativeU32(gr.completed_laps),
        .position = positiveU16(gr.position),
        .current_time_s = millis(gr.i_current_time),
        .last_time_s = millis(gr.i_last_time),
        .best_time_s = millis(gr.i_best_time),
    };
    state.data.session = .{
        .kind = sessionKind(gr.sessionValue().label()),
        .state = sessionState(@tagName(gr.statusValue())),
        .remaining_time_s = millisFloat(gr.session_time_left),
    };
    return true;
}

pub fn normalizeAcc(state: *State, client: *sims.acc.Client) bool {
    state.clear();
    const p = client.physics();
    const gr = client.graphics();
    if (client.static()) |s| {
        var track: [256]u8 = undefined;
        var car: [256]u8 = undefined;
        var first: [128]u8 = undefined;
        var last: [128]u8 = undefined;
        state.setTrack(s.trackUtf8(&track));
        state.setCar(s.carModelUtf8(&car));
        state.setDriver(joinName(&state.driver_buf, s.playerNameUtf8(&first), s.playerSurnameUtf8(&last)));
    }
    fillAcLike(state, p.speed_kmh, p.gear, p.rpm, p.fuel, p.gas, p.brake, p.clutch, p.acc_g, p.heading, p.pitch, p.roll);
    state.data.controls.steering_rad = p.steer_angle;
    state.data.lap = .{
        .number = nonNegativeU32(gr.completed_laps),
        .position = positiveU16(gr.position),
        .current_time_s = millis(gr.i_current_time),
        .last_time_s = millis(gr.i_last_time),
        .best_time_s = millis(gr.i_best_time),
    };
    state.data.session = .{
        .kind = sessionKind(gr.sessionValue().label()),
        .state = sessionState(@tagName(gr.statusValue())),
        .remaining_time_s = millisFloat(gr.session_time_left),
    };
    return true;
}

pub fn normalizeAce(state: *State, client: *sims.ace.Client) bool {
    state.clear();
    const p = client.physics();
    const gr = client.graphics();
    if (client.static()) |s| state.setTrack(s.trackName());
    state.setCar(gr.carModel());
    state.setDriver(joinName(&state.driver_buf, gr.driverName(), gr.driverSurname()));
    fillAcLike(state, p.speed_kmh, p.gear, p.rpms, p.fuel, p.gas, p.brake, p.clutch, p.acc_g, p.heading, p.pitch, p.roll);
    // ACE acc_g is [lat, long, vert]; fillAcLike remaps classic AC Y-up [lat, vert, long].
    state.data.motion.acceleration_mps2 = .{
        .x = p.acc_g[0] * g,
        .y = p.acc_g[1] * g,
        .z = p.acc_g[2] * g,
    };
    state.data.controls.steering_rad = @as(f32, @floatFromInt(gr.steer_degrees)) * deg_to_rad;
    state.data.lap = .{
        .number = nonNegativeU32(gr.total_lap_count),
        .position = positiveU16(gr.current_pos),
        .current_time_s = millis(gr.current_lap_time_ms),
        .last_time_s = millis(gr.last_laptime_ms),
        .best_time_s = millis(gr.best_laptime_ms),
    };
    if (client.static()) |s| state.data.session.kind = sessionKind(s.sessionValue().label());
    return true;
}

pub fn normalizeAcr(state: *State, client: *sims.acr.Client) bool {
    state.clear();
    const p = client.physics();
    const gr = client.graphics();
    if (client.static()) |s| {
        var track: [256]u8 = undefined;
        var car: [256]u8 = undefined;
        var first: [128]u8 = undefined;
        var last: [128]u8 = undefined;
        state.setTrack(s.trackUtf8(&track));
        state.setCar(s.carModelUtf8(&car));
        state.setDriver(joinName(&state.driver_buf, s.playerNameUtf8(&first), s.playerSurnameUtf8(&last)));
    }
    fillAcLike(state, p.speed_kmh, p.gear, p.rpms, p.fuel, p.gas, p.brake, p.clutch, p.acc_g, p.heading, p.pitch, p.roll);
    state.data.controls.steering_rad = p.steer_angle;
    state.data.lap = .{
        .number = nonNegativeU32(gr.completed_laps),
        .position = positiveU16(gr.position),
        .current_time_s = millis(gr.i_current_time),
        .last_time_s = millis(gr.i_last_time),
        .best_time_s = millis(gr.i_best_time),
    };
    state.data.session = .{
        .kind = sessionKind(gr.sessionValue().label()),
        .remaining_time_s = millisFloat(gr.session_time_left),
    };
    return true;
}

fn fillAcLike(
    state: *State,
    speed_kmh: f32,
    gear: i32,
    rpm: i32,
    fuel: f32,
    throttle: f32,
    brake: f32,
    clutch: f32,
    acceleration_g: [3]f32,
    yaw: f32,
    pitch: f32,
    roll: f32,
) void {
    state.data.vehicle = .{
        .speed_mps = speed_kmh / 3.6,
        .gear = safeGear(gear - 1),
        .engine_rpm = @floatFromInt(rpm),
        .fuel_liters = fuel,
    };
    state.data.controls = .{
        .throttle = unit(throttle),
        .brake = unit(brake),
        .clutch = unit(clutch),
    };
    state.data.motion = .{
        .acceleration_mps2 = .{
            .x = acceleration_g[0] * g,
            .y = acceleration_g[2] * g,
            .z = acceleration_g[1] * g,
        },
        .orientation_rad = .{ .x = yaw, .y = pitch, .z = roll },
    };
}

pub fn normalizeAms(state: *State, client: *sims.ams.Client) bool {
    state.clear();
    const s = client.shared();
    normalizePcars(state, s);
    return true;
}

pub fn normalizeAms2(state: *State, client: *sims.ams2.Client) bool {
    state.clear();
    const s = client.shared();
    normalizePcars(state, s);
    return true;
}

fn normalizePcars(state: *State, s: anytype) void {
    state.setTrack(joinTrack(&state.track_buf, s.trackLocation(), s.trackVariation()));
    state.setCar(s.carName());
    state.setDriver(s.playerName());
    state.data.vehicle = .{
        .speed_mps = s.speedKmh() / 3.6,
        .gear = safeGear(s.displayGear()),
        .engine_rpm = s.rpm,
        .max_engine_rpm = s.max_rpm,
        .fuel_liters = if (s.fuel_capacity > 0) s.fuel_level * s.fuel_capacity else null,
    };
    state.data.controls = .{
        .throttle = unit(s.throttle),
        .brake = unit(s.brake),
        .clutch = unit(s.clutch),
        .steering_rad = s.steering * std.math.pi,
    };
    state.data.motion = .{
        .acceleration_mps2 = .{ .x = s.local_acceleration[0], .y = s.local_acceleration[2], .z = s.local_acceleration[1] },
        .orientation_rad = .{ .x = s.orientation[1], .y = s.orientation[0], .z = s.orientation[2] },
    };
    state.data.lap = .{
        .number = if (s.viewedParticipant()) |p| nonNegativeU32(p.current_lap) else null,
        .position = if (s.viewedParticipant()) |p| positiveU16(p.race_position) else null,
        .current_time_s = positiveFloat(s.current_time),
        .last_time_s = positiveFloat(s.last_lap_time),
        .best_time_s = positiveFloat(s.best_lap_time),
    };
    state.data.session = .{
        .kind = sessionKind(s.sessionStateValue().label()),
        .state = sessionState(s.raceStateValue().label()),
        .remaining_time_s = if (s.event_time_remaining >= 0) s.event_time_remaining / 1000.0 else null,
    };
}

pub fn normalizeR3e(state: *State, client: *sims.r3e.Client) bool {
    state.clear();
    const s = client.shared();
    state.setTrack(joinTrack(&state.track_buf, s.trackName(), s.layoutName()));
    state.setCar(s.vehicle_info.nameUtf8());
    state.setDriver(s.playerName());
    state.data.vehicle = .{
        .speed_mps = s.speedKmh() / 3.6,
        .gear = safeGear(s.displayGear()),
        .engine_rpm = s.engineRpm(),
        .fuel_liters = positiveFloat(s.fuel_left),
    };
    state.data.controls = .{
        .throttle = optionalNonNegativeUnit(s.throttle),
        .brake = optionalNonNegativeUnit(s.brake),
        .clutch = optionalNonNegativeUnit(s.clutch),
        .steering_rad = s.steer_input_raw * @as(f32, @floatFromInt(if (s.steer_lock_degrees > 0) s.steer_lock_degrees else 1)) * deg_to_rad,
    };
    state.data.motion = .{
        .acceleration_mps2 = .{ .x = s.local_acceleration.x, .y = -s.local_acceleration.z, .z = s.local_acceleration.y },
        .orientation_rad = .{ .x = s.car_orientation.yaw, .y = s.car_orientation.pitch, .z = s.car_orientation.roll },
    };
    state.data.lap = .{
        .number = nonNegativeU32(s.completed_laps),
        .position = positiveU16(s.position),
        .current_time_s = positiveFloat(s.lap_time_current_self),
        .last_time_s = positiveFloat(s.lap_time_previous_self),
        .best_time_s = positiveFloat(s.lap_time_best_self),
    };
    state.data.session = .{
        .kind = sessionKind(s.sessionTypeValue().label()),
        .state = sessionState(s.sessionPhaseValue().label()),
        .remaining_time_s = positiveFloat(s.session_time_remaining),
    };
    return true;
}

pub fn normalizeLmu(state: *State, client: *sims.lmu.Client) bool {
    state.clear();
    const t = client.telemetry();
    const s = client.session();
    const v = client.vehicle();
    var track: [256]u8 = undefined;
    var car: [256]u8 = undefined;
    var driver: [256]u8 = undefined;
    state.setTrack(s.trackNameUtf8(&track));
    state.setCar(t.vehicleNameUtf8(&car));
    state.setDriver(v.driverNameUtf8(&driver));
    state.data.vehicle = .{
        .speed_mps = @floatCast(t.speedKmh() / 3.6),
        .gear = safeGear(t.gear),
        .engine_rpm = @floatCast(t.engine_rpm),
        .max_engine_rpm = @floatCast(t.engine_max_rpm),
        .fuel_liters = @floatCast(t.fuel),
    };
    state.data.controls = .{
        .throttle = unit(@floatCast(t.unfiltered_throttle)),
        .brake = unit(@floatCast(t.unfiltered_brake)),
        .clutch = unit(@floatCast(t.unfiltered_clutch)),
    };
    const euler = matrixToEuler(t.ori);
    state.data.motion = .{
        .acceleration_mps2 = .{
            .x = @floatCast(t.local_accel.x),
            .y = @floatCast(-t.local_accel.z),
            .z = @floatCast(t.local_accel.y),
        },
        .orientation_rad = euler,
    };
    state.data.lap = .{
        .number = nonNegativeU32(v.total_laps),
        .position = positiveU16(v.place),
        .current_time_s = positiveFloat(s.current_et - v.lap_start_et),
        .last_time_s = positiveFloat(v.last_lap_time),
        .best_time_s = positiveFloat(v.best_lap_time),
    };
    state.data.session = .{
        .kind = sessionKind(s.sessionValue().label()),
        .state = sessionState(s.gamePhaseValue().label()),
        .elapsed_time_s = positiveFloat(s.current_et),
        .remaining_time_s = positiveFloat(s.session_time_remaining),
    };
    return true;
}

fn matrixToEuler(ori: [3]sims.lmu.protocol.TelemVect3) types.Vec3 {
    return .{
        .x = @floatCast(std.math.atan2(ori[0].z, ori[2].z)),
        .y = @floatCast(std.math.asin(std.math.clamp(-ori[1].z, -1.0, 1.0))),
        .z = @floatCast(std.math.atan2(ori[1].x, ori[1].y)),
    };
}

pub fn normalizeFh6(state: *State, client: *sims.fh6.Client) bool {
    state.clear();
    const p = client.packet();
    var car: [160]u8 = undefined;
    state.setCar(p.formatCarSummary(&car));
    state.data.vehicle = .{
        .speed_mps = p.speed,
        .gear = safeGear(p.displayGear()),
        .engine_rpm = p.current_engine_rpm,
        .max_engine_rpm = p.engine_max_rpm,
    };
    state.data.controls = .{
        .throttle = @as(f32, @floatFromInt(p.accel)) / 255.0,
        .brake = @as(f32, @floatFromInt(p.brake)) / 255.0,
        .clutch = @as(f32, @floatFromInt(p.clutch)) / 255.0,
        .steering_rad = @as(f32, @floatFromInt(p.steer)) * (900.0 / 127.0) * deg_to_rad,
    };
    state.data.motion = .{
        // Forza local space: X right (lat), Y up (vert), Z forward (long).
        .acceleration_mps2 = .{ .x = p.acceleration_x, .y = p.acceleration_z, .z = p.acceleration_y },
        .orientation_rad = .{ .x = p.yaw, .y = p.pitch, .z = p.roll },
    };
    state.data.lap = .{
        .number = nonNegativeU32(p.lap_number),
        .position = positiveU16(p.race_position),
        .current_time_s = positiveFloat(p.current_lap),
        .last_time_s = positiveFloat(p.last_lap),
        .best_time_s = positiveFloat(p.best_lap),
    };
    state.data.session = .{
        .state = if (p.is_race_on != 0) .active else .other,
        .elapsed_time_s = positiveFloat(p.current_race_time),
    };
    return true;
}

pub fn normalizeBeamng(state: *State, client: *sims.beamng.Client) bool {
    state.clear();
    const p = client.packet();
    state.setCar(p.carName());
    state.data.vehicle = .{
        .speed_mps = p.speed,
        .gear = safeGear(p.displayGear()),
        .engine_rpm = p.rpm,
    };
    state.data.controls = .{
        .throttle = optionalUnit(p.throttle),
        .brake = optionalUnit(p.brake),
        .clutch = optionalUnit(p.clutch),
    };
    state.data.session = .{
        .state = .active,
    };
    return true;
}

pub fn normalizeIracing(state: *State, client: *sims.iracing.Client) bool {
    refreshIracing(state, client) catch return false;
    state.clearData();
    const variables = client.variables();
    const i = state.iracing_indices;
    state.data.session.kind = state.iracing_session_kind;
    state.data.vehicle = .{
        .speed_mps = readFloat(variables, i.speed),
        .gear = if (readInt(variables, i.gear)) |value| safeGear(value) else null,
        .engine_rpm = readFloat(variables, i.rpm),
        .fuel_liters = readFloat(variables, i.fuel),
    };
    state.data.controls = .{
        .throttle = optionalUnit(readFloat(variables, i.throttle)),
        .brake = optionalUnit(readFloat(variables, i.brake)),
        .clutch = optionalUnit(readFloat(variables, i.clutch)),
        .steering_rad = readFloat(variables, i.steering),
    };
    if (readFloat(variables, i.lat_accel)) |x| {
        state.data.motion.acceleration_mps2 = .{
            .x = x,
            .y = readFloat(variables, i.long_accel) orelse 0,
            .z = readFloat(variables, i.vert_accel) orelse 0,
        };
    }
    if (readFloat(variables, i.yaw)) |yaw| {
        state.data.motion.orientation_rad = .{
            .x = yaw,
            .y = readFloat(variables, i.pitch) orelse 0,
            .z = readFloat(variables, i.roll) orelse 0,
        };
    }
    state.data.lap = .{
        .number = if (readInt(variables, i.lap)) |value| nonNegativeU32(value) else null,
        .current_time_s = positiveFloat(readFloat(variables, i.lap_current)),
        .last_time_s = positiveFloat(readFloat(variables, i.lap_last)),
        .best_time_s = positiveFloat(readFloat(variables, i.lap_best)),
    };
    state.data.session.elapsed_time_s = positiveFloat(readFloat(variables, i.session_time));
    if (readInt(variables, i.session_state)) |value| {
        state.data.session.state = iracingSessionState(@enumFromInt(value));
    }
    return true;
}

fn refreshIracing(state: *State, client: *sims.iracing.Client) !void {
    const variables = client.variables();
    if (state.iracing_variables_version != variables.version()) {
        const names = sims.iracing.keys.var_name;
        state.iracing_indices = .{
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
            .lat_accel = try variables.find(names.lat_accel),
            .long_accel = try variables.find(names.long_accel),
            .vert_accel = try variables.find(names.vert_accel),
            .yaw = try variables.find(names.yaw),
            .pitch = try variables.find(names.pitch),
            .roll = try variables.find(names.roll),
            .session_state = try variables.find(names.session_state),
            .session_time = try variables.find(names.session_time),
        };
        state.iracing_variables_version = variables.version();
    }
    const session_version = client.session().version() orelse return;
    if (state.iracing_session == null or state.iracing_session.?.version != session_version) {
        var replacement = try client.session().snapshot();
        errdefer replacement.deinit();
        if (state.iracing_session) |*old| old.deinit();
        state.iracing_session = replacement;
        refreshIracingIdentity(state);
    }
}

fn refreshIracingIdentity(state: *State) void {
    if (state.iracing_session) |*session| {
        var temp: [256]u8 = undefined;
        state.setTrack(sessionString(session, sims.iracing.keys.session.weekend_info, sims.iracing.keys.session.track_display_name, &temp) orelse
            sessionString(session, sims.iracing.keys.session.weekend_info, sims.iracing.keys.session.track_name, &temp));
        state.setCar(playerDriverString(session, sims.iracing.keys.driver.car_screen_name, &temp) orelse
            playerDriverString(session, sims.iracing.keys.driver.car_path, &temp));
        state.setDriver(playerDriverString(session, sims.iracing.keys.driver.user_name, &temp));
        state.iracing_session_kind = if (sessionString(
            session,
            sims.iracing.keys.session.weekend_info,
            sims.iracing.keys.session.session_type,
            &temp,
        )) |label| sessionKind(label) else null;
    }
}

fn readInt(variables: sims.iracing.VariablesView, variable: ?sims.iracing.Variable) ?i32 {
    const value = variables.value(variable orelse return null) catch return null;
    return value.asInt();
}

fn readFloat(variables: sims.iracing.VariablesView, variable: ?sims.iracing.Variable) ?f32 {
    const value = variables.value(variable orelse return null) catch return null;
    return @floatCast(value.asFloat() orelse return null);
}

fn sessionString(snapshot: *const sims.iracing.SessionSnapshot, section: []const u8, key: []const u8, buffer: []u8) ?[]const u8 {
    const scalar = (snapshot.query(&.{ .{ .key = section }, .{ .key = key } }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}

fn playerDriverString(snapshot: *const sims.iracing.SessionSnapshot, key: []const u8, buffer: []u8) ?[]const u8 {
    const ir = sims.iracing;
    const player = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.driver_car_idx },
    }) catch return null) orelse return null;
    const player_index = player.asInt() catch return null;
    const scalar = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.drivers },
        .{ .select = .{ .key = ir.keys.driver.car_idx, .value = .{ .int = player_index } } },
        .{ .key = key },
    }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}

fn copyText(destination: []u8, value: ?[]const u8) usize {
    const source = value orelse return 0;
    const len = @min(destination.len, source.len);
    if (len == 0 or destination.ptr == source.ptr) return len;
    @memcpy(destination[0..len], source[0..len]);
    return len;
}

fn joinName(destination: []u8, first_opt: ?[]const u8, last_opt: ?[]const u8) ?[]const u8 {
    const first = first_opt orelse "";
    const last = last_opt orelse "";
    if (first.len == 0 and last.len == 0) return null;
    if (first.len == 0) return last;
    if (last.len == 0) return first;
    return std.fmt.bufPrint(destination, "{s} {s}", .{ first, last }) catch first;
}

fn joinTrack(destination: []u8, track: []const u8, layout: []const u8) ?[]const u8 {
    if (track.len == 0) return null;
    if (layout.len == 0) return track;
    return std.fmt.bufPrint(destination, "{s} ({s})", .{ track, layout }) catch track;
}

fn unit(value: f32) f32 {
    return std.math.clamp(value, 0, 1);
}

fn optionalUnit(value: ?f32) ?f32 {
    return unit(value orelse return null);
}

/// R3E (and similar) use negative floats as N/A sentinels.
fn optionalNonNegativeUnit(value: f32) ?f32 {
    if (value < 0) return null;
    return unit(value);
}

fn safeGear(value: anytype) ?i8 {
    const gear: i64 = @intCast(value);
    if (gear < -1 or gear > std.math.maxInt(i8)) return null;
    return @intCast(gear);
}

fn nonNegativeU32(value: anytype) ?u32 {
    if (value < 0) return null;
    return @intCast(value);
}

fn positiveU16(value: anytype) ?u16 {
    if (value <= 0 or value > std.math.maxInt(u16)) return null;
    return @intCast(value);
}

fn millis(value: anytype) ?f32 {
    if (value < 0) return null;
    return @as(f32, @floatFromInt(value)) / 1000.0;
}

fn millisFloat(value: anytype) ?f32 {
    if (value < 0) return null;
    return @as(f32, @floatCast(value)) / 1000.0;
}

fn positiveFloat(value: anytype) ?f32 {
    const result: f32 = switch (@typeInfo(@TypeOf(value))) {
        .optional => @floatCast(value orelse return null),
        else => @floatCast(value),
    };
    return if (result >= 0 and std.math.isFinite(result)) result else null;
}

fn sessionKind(label: []const u8) ?types.SessionKind {
    if (containsIgnoreCase(label, "practice")) return .practice;
    if (containsIgnoreCase(label, "qual")) return .qualifying;
    if (containsIgnoreCase(label, "race")) return .race;
    if (containsIgnoreCase(label, "time") or containsIgnoreCase(label, "hotlap")) return .time_attack;
    return if (label.len == 0) null else .other;
}

fn sessionState(label: []const u8) ?types.SessionState {
    if (containsIgnoreCase(label, "garage")) return .garage;
    if (containsIgnoreCase(label, "warmup") or containsIgnoreCase(label, "countdown")) return .warmup;
    if (containsIgnoreCase(label, "green") or containsIgnoreCase(label, "active") or containsIgnoreCase(label, "live") or containsIgnoreCase(label, "racing")) return .active;
    if (containsIgnoreCase(label, "pause")) return .paused;
    if (containsIgnoreCase(label, "finish") or containsIgnoreCase(label, "checkered")) return .finished;
    return if (label.len == 0) null else .other;
}

fn iracingSessionState(value: sims.iracing.enums.SessionState) ?types.SessionState {
    return switch (value) {
        .invalid => null,
        .get_in_car => .garage,
        .warmup, .parade_laps => .warmup,
        .racing => .active,
        .checkered, .cool_down => .finished,
        else => .other,
    };
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

test "text storage truncates without allocation" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const long = "x" ** 200;
    state.setTrack(long);
    try std.testing.expectEqual(state.track_buf.len, state.track_len);
    state.setDriver(joinName(&state.driver_buf, "Ada", "Lovelace"));
    try std.testing.expectEqualStrings("Ada Lovelace", state.snapshot(.ac, 42).identity.driver.?);
}

test "common conversions preserve absence and units" {
    try std.testing.expectEqual(@as(?i8, -1), safeGear(-1));
    try std.testing.expectEqual(@as(?i8, null), safeGear(999));
    try std.testing.expectApproxEqAbs(@as(f32, 1), unit(2), 0.0001);
    try std.testing.expectEqual(@as(?f32, null), positiveFloat(@as(f32, -1)));
}

test "AC protocol fixture normalizes canonical units" {
    var physics: sims.ac.Physics = .{ .speed_kmh = 72, .gear = 3, .rpms = 6000, .fuel = 20 };
    var graphics: sims.ac.Graphics = .{ .completed_laps = 2, .position = 4, .i_current_time = 12_500 };
    var static: sims.ac.Static = .{};
    var client: sims.ac.Client = .{
        .allocator = std.testing.allocator,
        .phys_mem = undefined,
        .gfx_mem = undefined,
        .static_mem = undefined,
        .phys = &physics,
        .gfx = &graphics,
        .stat = &static,
    };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(normalizeAc(&state, &client));
    const sample = state.snapshot(.ac, 7);
    try std.testing.expectApproxEqAbs(@as(f32, 20), sample.vehicle.speed_mps.?, 0.001);
    try std.testing.expectEqual(@as(?i8, 2), sample.vehicle.gear);
    try std.testing.expectApproxEqAbs(@as(f32, 12.5), sample.lap.current_time_s.?, 0.001);
}

test "FH6 protocol fixture normalizes inputs" {
    var client: sims.fh6.Client = .{ .listener = undefined };
    client.snapshot.speed = 50;
    client.snapshot.gear = 4;
    client.snapshot.accel = 255;
    client.snapshot.brake = 128;
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(normalizeFh6(&state, &client));
    const sample = state.snapshot(.fh6, 8);
    try std.testing.expectApproxEqAbs(@as(f32, 50), sample.vehicle.speed_mps.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sample.controls.throttle.?, 0.001);
}

test "BeamNG OutGauge fixture normalizes inputs" {
    var client: sims.beamng.Client = .{ .listener = undefined };
    client.snapshot.speed = 40;
    client.snapshot.gear = 3;
    client.snapshot.throttle = 0.75;
    client.snapshot.brake = 0.25;
    client.snapshot.rpm = 3500;
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(normalizeBeamng(&state, &client));
    const sample = state.snapshot(.beamng, 9);
    try std.testing.expectApproxEqAbs(@as(f32, 40), sample.vehicle.speed_mps.?, 0.001);
    try std.testing.expectEqual(@as(?i8, 2), sample.vehicle.gear);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), sample.controls.throttle.?, 0.001);
    try std.testing.expectEqualStrings("beam", sample.identity.car.?);
}
