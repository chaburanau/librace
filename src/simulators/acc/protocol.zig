//! Assetto Corsa Competizione shared-memory layout.
//!
//! Reference: Kunos' ACC Shared Memory Documentation v1.8.12, cross-checked against
//! maintained community bindings (`acc_shared_memory_rs`, `PyAccSharedMemory`, and
//! ACC overlay readers). ACC reuses classic AC's three Windows mapping names but the
//! physics/graphics structs are larger and have ACC-specific fields.
//!
//! Layout notes:
//! - The C/C++ structs are declared with `#pragma pack(4)`.
//! - Strings are Windows `wchar_t` (UTF-16LE), represented as `[N]u16`.
//! - Live physics and graphics pages have `packetId` at offset 0.
//! - `currentMaxRpm` is documented as a float in some copies of the v1.8.12 PDF, but
//!   current ACC builds write an `int32` there; reading it as float produces a denormal.

const std = @import("std");

/// Windows named shared-memory tags. ACC intentionally uses the same tags as classic AC.
pub const physics_map_name = "Local\\acpmf_physics";
pub const graphics_map_name = "Local\\acpmf_graphics";
pub const static_map_name = "Local\\acpmf_static";

pub const Status = enum(i32) {
    off = 0,
    replay = 1,
    live = 2,
    pause = 3,
    _,
};

pub const SessionType = enum(i32) {
    unknown = -1,
    practice = 0,
    qualify = 1,
    race = 2,
    hotlap = 3,
    time_attack = 4,
    drift = 5,
    drag = 6,
    _,

    pub fn label(self: SessionType) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .practice => "Practice",
            .qualify => "Qualify",
            .race => "Race",
            .hotlap => "Hotlap",
            .time_attack => "Time Attack",
            .drift => "Drift",
            .drag => "Drag",
            _ => "?",
        };
    }
};

pub const FlagType = enum(i32) {
    none = 0,
    blue = 1,
    yellow = 2,
    black = 3,
    white = 4,
    checkered = 5,
    penalty = 6,
    green = 7,
    orange = 8,
    _,
};

pub const PenaltyType = enum(i32) {
    none = 0,
    drive_through_cutting = 1,
    stop_and_go_10_cutting = 2,
    stop_and_go_20_cutting = 3,
    stop_and_go_30_cutting = 4,
    disqualified_cutting = 5,
    remove_best_lap_time = 6,
    drive_through_pit_speeding = 7,
    stop_and_go_10_pit_speeding = 8,
    stop_and_go_20_pit_speeding = 9,
    stop_and_go_30_pit_speeding = 10,
    disqualified_pit_speeding = 11,
    disqualified_ignored_mandatory_pit = 12,
    post_race_time = 13,
    disqualified_trolling = 14,
    disqualified_pit_entry = 15,
    disqualified_pit_exit = 16,
    disqualified_wrong_way = 17,
    drive_through_ignored_driver_stint = 18,
    disqualified_ignored_driver_stint = 19,
    disqualified_exceeded_driver_stint_limit = 20,
    _,
};

pub const TrackGripStatus = enum(i32) {
    green = 0,
    fast = 1,
    optimum = 2,
    greasy = 3,
    damp = 4,
    wet = 5,
    flooded = 6,
    _,

    pub fn label(self: TrackGripStatus) []const u8 {
        return switch (self) {
            .green => "Green",
            .fast => "Fast",
            .optimum => "Optimum",
            .greasy => "Greasy",
            .damp => "Damp",
            .wet => "Wet",
            .flooded => "Flooded",
            _ => "?",
        };
    }
};

pub const RainIntensity = enum(i32) {
    none = 0,
    drizzle = 1,
    light = 2,
    medium = 3,
    heavy = 4,
    thunderstorm = 5,
    _,

    pub fn label(self: RainIntensity) []const u8 {
        return switch (self) {
            .none => "Dry",
            .drizzle => "Drizzle",
            .light => "Light Rain",
            .medium => "Rain",
            .heavy => "Heavy Rain",
            .thunderstorm => "Storm",
            _ => "?",
        };
    }
};

/// Raw physics telemetry, updated every simulation step (`Local\\acpmf_physics`).
pub const Physics = extern struct {
    packet_id: i32 = 0,
    gas: f32 = 0,
    brake: f32 = 0,
    fuel: f32 = 0,
    gear: i32 = 0,
    rpm: i32 = 0,
    steer_angle: f32 = 0,
    speed_kmh: f32 = 0,
    velocity: [3]f32 = .{ 0, 0, 0 },
    acc_g: [3]f32 = .{ 0, 0, 0 },
    wheel_slip: [4]f32 = .{ 0, 0, 0, 0 },
    wheel_load: [4]f32 = .{ 0, 0, 0, 0 },
    wheel_pressure: [4]f32 = .{ 0, 0, 0, 0 },
    wheel_angular_speed: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_wear: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_dirty_level: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_core_temp: [4]f32 = .{ 0, 0, 0, 0 },
    camber_rad: [4]f32 = .{ 0, 0, 0, 0 },
    suspension_travel: [4]f32 = .{ 0, 0, 0, 0 },
    drs: f32 = 0,
    tc: f32 = 0,
    heading: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    cg_height: f32 = 0,
    car_damage: [5]f32 = .{ 0, 0, 0, 0, 0 },
    number_of_tyres_out: i32 = 0,
    pit_limiter_on: i32 = 0,
    abs: f32 = 0,
    kers_charge: f32 = 0,
    kers_input: f32 = 0,
    autoshifter_on: i32 = 0,
    ride_height: [2]f32 = .{ 0, 0 },
    turbo_boost: f32 = 0,
    ballast: f32 = 0,
    air_density: f32 = 0,
    air_temp: f32 = 0,
    road_temp: f32 = 0,
    local_angular_vel: [3]f32 = .{ 0, 0, 0 },
    final_ff: f32 = 0,
    performance_meter: f32 = 0,
    engine_brake: i32 = 0,
    ers_recovery_level: i32 = 0,
    ers_power_level: i32 = 0,
    ers_heat_charging: i32 = 0,
    ers_is_charging: i32 = 0,
    kers_current_kj: f32 = 0,
    drs_available: i32 = 0,
    drs_enabled: i32 = 0,
    brake_temp: [4]f32 = .{ 0, 0, 0, 0 },
    clutch: f32 = 0,
    tyre_temp_i: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_temp_m: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_temp_o: [4]f32 = .{ 0, 0, 0, 0 },
    is_ai_controlled: i32 = 0,
    tyre_contact_point: [4][3]f32 = @splat(@splat(0)),
    tyre_contact_normal: [4][3]f32 = @splat(@splat(0)),
    tyre_contact_heading: [4][3]f32 = @splat(@splat(0)),
    brake_bias: f32 = 0,
    local_velocity: [3]f32 = .{ 0, 0, 0 },
    p2p_activation: i32 = 0,
    p2p_status: i32 = 0,
    current_max_rpm: i32 = 0,
    mz: [4]f32 = .{ 0, 0, 0, 0 },
    fx: [4]f32 = .{ 0, 0, 0, 0 },
    fy: [4]f32 = .{ 0, 0, 0, 0 },
    slip_ratio: [4]f32 = .{ 0, 0, 0, 0 },
    slip_angle: [4]f32 = .{ 0, 0, 0, 0 },
    tc_in_action: i32 = 0,
    abs_in_action: i32 = 0,
    suspension_damage: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_temp: [4]f32 = .{ 0, 0, 0, 0 },
    water_temp: f32 = 0,
    brake_pressure: [4]f32 = .{ 0, 0, 0, 0 },
    front_brake_compound: i32 = 0,
    rear_brake_compound: i32 = 0,
    pad_life: [4]f32 = .{ 0, 0, 0, 0 },
    disc_life: [4]f32 = .{ 0, 0, 0, 0 },
    ignition_on: i32 = 0,
    starter_engine_on: i32 = 0,
    is_engine_running: i32 = 0,
    kerb_vibration: f32 = 0,
    slip_vibrations: f32 = 0,
    g_vibrations: f32 = 0,
    abs_vibrations: f32 = 0,

    pub fn gearLabel(self: *const Physics, buf: []u8) []const u8 {
        return switch (self.gear) {
            0 => "R",
            1 => "N",
            else => std.fmt.bufPrint(buf, "{d}", .{self.gear - 1}) catch "?",
        };
    }
};

/// Session/HUD telemetry, updated once per rendered frame (`Local\\acpmf_graphics`).
pub const Graphics = extern struct {
    packet_id: i32 = 0,
    status: i32 = 0,
    session: i32 = 0,
    current_time: [15]u16 = @splat(0),
    last_time: [15]u16 = @splat(0),
    best_time: [15]u16 = @splat(0),
    split: [15]u16 = @splat(0),
    completed_laps: i32 = 0,
    position: i32 = 0,
    i_current_time: i32 = 0,
    i_last_time: i32 = 0,
    i_best_time: i32 = 0,
    session_time_left: f32 = 0,
    distance_traveled: f32 = 0,
    is_in_pit: i32 = 0,
    current_sector_index: i32 = 0,
    last_sector_time: i32 = 0,
    number_of_laps: i32 = 0,
    tyre_compound: [33]u16 = @splat(0),
    replay_time_multiplier: f32 = 0,
    normalized_car_position: f32 = 0,
    active_cars: i32 = 0,
    car_coordinates: [60][3]f32 = @splat(@splat(0)),
    car_id: [60]i32 = @splat(0),
    player_car_id: i32 = 0,
    penalty_time: f32 = 0,
    flag: i32 = 0,
    penalty: i32 = 0,
    ideal_line_on: i32 = 0,
    is_in_pit_lane: i32 = 0,
    surface_grip: f32 = 0,
    mandatory_pit_done: i32 = 0,
    wind_speed: f32 = 0,
    wind_direction: f32 = 0,
    is_setup_menu_visible: i32 = 0,
    main_display_index: i32 = 0,
    secondary_display_index: i32 = 0,
    tc: i32 = 0,
    tc_cut: i32 = 0,
    engine_map: i32 = 0,
    abs: i32 = 0,
    fuel_x_lap: f32 = 0,
    rain_lights: i32 = 0,
    flashing_lights: i32 = 0,
    lights_stage: i32 = 0,
    exhaust_temperature: f32 = 0,
    wiper_level: i32 = 0,
    driver_stint_total_time_left: i32 = 0,
    driver_stint_time_left: i32 = 0,
    rain_tyres: i32 = 0,
    session_index: i32 = 0,
    used_fuel: f32 = 0,
    delta_lap_time: [15]u16 = @splat(0),
    i_delta_lap_time: i32 = 0,
    estimated_lap_time: [15]u16 = @splat(0),
    i_estimated_lap_time: i32 = 0,
    is_delta_positive: i32 = 0,
    i_split: i32 = 0,
    is_valid_lap: i32 = 0,
    fuel_estimated_laps: f32 = 0,
    track_status: [33]u16 = @splat(0),
    missing_mandatory_pits: i32 = 0,
    clock: f32 = 0,
    direction_lights_left: i32 = 0,
    direction_lights_right: i32 = 0,
    global_yellow: i32 = 0,
    global_yellow1: i32 = 0,
    global_yellow2: i32 = 0,
    global_yellow3: i32 = 0,
    global_white: i32 = 0,
    global_green: i32 = 0,
    global_chequered: i32 = 0,
    global_red: i32 = 0,
    mfd_tyre_set: i32 = 0,
    mfd_fuel_to_add: f32 = 0,
    mfd_tyre_pressure_lf: f32 = 0,
    mfd_tyre_pressure_rf: f32 = 0,
    mfd_tyre_pressure_lr: f32 = 0,
    mfd_tyre_pressure_rr: f32 = 0,
    track_grip_status: i32 = 0,
    rain_intensity: i32 = 0,
    rain_intensity_in_10min: i32 = 0,
    rain_intensity_in_30min: i32 = 0,
    current_tyre_set: i32 = 0,
    strategy_tyre_set: i32 = 0,
    gap_ahead: i32 = 0,
    gap_behind: i32 = 0,

    pub fn statusValue(self: *const Graphics) Status {
        return @enumFromInt(self.status);
    }

    pub fn sessionValue(self: *const Graphics) SessionType {
        return @enumFromInt(self.session);
    }

    pub fn flagValue(self: *const Graphics) FlagType {
        return @enumFromInt(self.flag);
    }

    pub fn penaltyValue(self: *const Graphics) PenaltyType {
        return @enumFromInt(self.penalty);
    }

    pub fn trackGripStatusValue(self: *const Graphics) TrackGripStatus {
        return @enumFromInt(self.track_grip_status);
    }

    pub fn rainIntensityValue(self: *const Graphics) RainIntensity {
        return @enumFromInt(self.rain_intensity);
    }

    pub fn locationLabel(self: *const Graphics) []const u8 {
        if (self.is_in_pit != 0) return "Pit Box";
        if (self.is_in_pit_lane != 0) return "Pit Lane";
        return "Track";
    }
};

/// Static session/car metadata (`Local\\acpmf_static`), written on session load.
pub const Static = extern struct {
    sm_version: [15]u16 = @splat(0),
    ac_version: [15]u16 = @splat(0),
    number_of_sessions: i32 = 0,
    num_cars: i32 = 0,
    car_model: [33]u16 = @splat(0),
    track: [33]u16 = @splat(0),
    player_name: [33]u16 = @splat(0),
    player_surname: [33]u16 = @splat(0),
    player_nick: [33]u16 = @splat(0),
    sector_count: i32 = 0,
    max_torque: f32 = 0,
    max_power: f32 = 0,
    max_rpm: i32 = 0,
    max_fuel: f32 = 0,
    suspension_max_travel: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_radius: [4]f32 = .{ 0, 0, 0, 0 },
    max_turbo_boost: f32 = 0,
    deprecated_1: f32 = 0,
    deprecated_2: f32 = 0,
    penalties_enabled: i32 = 0,
    aid_fuel_rate: f32 = 0,
    aid_tire_rate: f32 = 0,
    aid_mechanical_damage: f32 = 0,
    allow_tyre_blankets: f32 = 0,
    aid_stability: f32 = 0,
    aid_auto_clutch: i32 = 0,
    aid_auto_blip: i32 = 0,
    has_drs: i32 = 0,
    has_ers: i32 = 0,
    has_kers: i32 = 0,
    kers_max_j: f32 = 0,
    engine_brake_settings_count: i32 = 0,
    ers_power_controller_count: i32 = 0,
    track_spline_length: f32 = 0,
    track_configuration: [33]u16 = @splat(0),
    ers_max_j: f32 = 0,
    is_timed_race: i32 = 0,
    has_extra_lap: i32 = 0,
    car_skin: [33]u16 = @splat(0),
    reversed_grid_positions: i32 = 0,
    pit_window_start: i32 = 0,
    pit_window_end: i32 = 0,
    is_online: i32 = 0,
    dry_tyres_name: [33]u16 = @splat(0),
    wet_tyres_name: [33]u16 = @splat(0),
};

/// Decode a UTF-16LE (`wchar_t`) buffer into `out` as UTF-8, truncating at NUL.
pub fn wcharToUtf8(src_bytes: []const u8, out: []u8) ?[]const u8 {
    var units: [256]u16 = undefined;
    const max_units = @min(src_bytes.len / 2, units.len);
    var len: usize = 0;
    while (len < max_units) : (len += 1) {
        const cu = std.mem.readInt(u16, src_bytes[len * 2 ..][0..2], .little);
        if (cu == 0) break;
        units[len] = cu;
    }
    const written = std.unicode.utf16LeToUtf8(out, units[0..len]) catch return null;
    return out[0..written];
}

/// `packetId` lives at offset 0 of both live pages; read it without a full struct copy.
pub fn readPacketId(view: []const u8) ?i32 {
    if (view.len < 4) return null;
    return std.mem.readInt(i32, view[0..4], .little);
}

test "physics layout matches ACC v1.8.12 offsets" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Physics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Physics, "gear"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(Physics, "rpm"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Physics, "speed_kmh"));
    try std.testing.expectEqual(@as(usize, 416), @offsetOf(Physics, "is_ai_controlled"));
    try std.testing.expectEqual(@as(usize, 564), @offsetOf(Physics, "brake_bias"));
    try std.testing.expectEqual(@as(usize, 588), @offsetOf(Physics, "current_max_rpm"));
    try std.testing.expectEqual(@as(usize, 716), @offsetOf(Physics, "brake_pressure"));
    try std.testing.expectEqual(@as(usize, 800), @sizeOf(Physics));
}

test "graphics layout includes ACC extension block" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Graphics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 176), @offsetOf(Graphics, "tyre_compound"));
    try std.testing.expectEqual(@as(usize, 252), @offsetOf(Graphics, "active_cars"));
    try std.testing.expectEqual(@as(usize, 256), @offsetOf(Graphics, "car_coordinates"));
    try std.testing.expectEqual(@as(usize, 976), @offsetOf(Graphics, "car_id"));
    try std.testing.expectEqual(@as(usize, 1268), @offsetOf(Graphics, "tc"));
    try std.testing.expectEqual(@as(usize, 1556), @offsetOf(Graphics, "track_grip_status"));
    try std.testing.expectEqual(@as(usize, 1588), @sizeOf(Graphics));
}

test "static layout includes ACC tyre-name additions" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Static, "sm_version"));
    try std.testing.expectEqual(@as(usize, 68), @offsetOf(Static, "car_model"));
    try std.testing.expectEqual(@as(usize, 456), @offsetOf(Static, "deprecated_1"));
    try std.testing.expectEqual(@as(usize, 684), @offsetOf(Static, "is_online"));
    try std.testing.expectEqual(@as(usize, 688), @offsetOf(Static, "dry_tyres_name"));
    try std.testing.expectEqual(@as(usize, 820), @sizeOf(Static));
}

test "wcharToUtf8 decodes a UTF-16LE value and stops at NUL" {
    const src = [_]u8{ 'S', 0, 'p', 0, 'a', 0, 0, 0, 'X', 0 };
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Spa", wcharToUtf8(&src, &out).?);
}

test "readPacketId reads the leading counter" {
    var phys: Physics = .{};
    phys.packet_id = 42;
    try std.testing.expectEqual(@as(i32, 42), readPacketId(std.mem.asBytes(&phys)).?);
}
