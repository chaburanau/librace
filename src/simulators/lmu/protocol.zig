//! Le Mans Ultimate native shared-memory layout.
//!
//! Reference: Studio 397 headers shipped with LMU:
//! `Support/SharedMemoryInterface/{SharedMemoryInterface.hpp,InternalsPlugin.hpp}`.
//!
//! Layout notes:
//! - `TelemInfoV01`, `VehicleScoringInfoV01`, `ScoringInfoV01`, and their nested telemetry
//!   structs are declared under `#pragma pack(push, 4)`.
//! - Windows C/C++ `long` is 32-bit.
//! - Strings are fixed-size ANSI `char` buffers, not UTF-16.

const std = @import("std");

pub const mem_map_name = "LMU_Data";
pub const data_event_name = "LMU_Data_Event";
pub const lock_map_name = "LMU_SharedMemoryLockData";
pub const lock_event_name = "LMU_SharedMemoryLockEvent";

pub const max_vehicles = 104;
pub const max_path = 260;
pub const scoring_stream_size = 65536;

pub const SessionType = enum(i32) {
    test_day = 0,
    practice1 = 1,
    practice2 = 2,
    practice3 = 3,
    practice4 = 4,
    qualifying1 = 5,
    qualifying2 = 6,
    qualifying3 = 7,
    qualifying4 = 8,
    warmup = 9,
    race1 = 10,
    race2 = 11,
    race3 = 12,
    race4 = 13,
    _,

    pub fn label(self: SessionType) []const u8 {
        return switch (self) {
            .test_day => "Test Day",
            .practice1, .practice2, .practice3, .practice4 => "Practice",
            .qualifying1, .qualifying2, .qualifying3, .qualifying4 => "Qualifying",
            .warmup => "Warmup",
            .race1, .race2, .race3, .race4 => "Race",
            _ => "?",
        };
    }
};

pub const GamePhase = enum(u8) {
    before_session = 0,
    reconnaissance = 1,
    grid_walk = 2,
    formation = 3,
    start_countdown = 4,
    green_flag = 5,
    full_course_yellow = 6,
    session_stopped = 7,
    session_over = 8,
    paused = 9,
    _,

    pub fn label(self: GamePhase) []const u8 {
        return switch (self) {
            .before_session => "Before Session",
            .reconnaissance => "Recon",
            .grid_walk => "Grid Walk",
            .formation => "Formation",
            .start_countdown => "Starting",
            .green_flag => "Green",
            .full_course_yellow => "FCY",
            .session_stopped => "Stopped",
            .session_over => "Over",
            .paused => "Paused",
            _ => "?",
        };
    }
};

pub const VehicleClass = enum(u8) {
    hypercar = 0x00,
    lmp2_elms = 0x02,
    lmp2 = 0x03,
    lmp3 = 0x04,
    gte = 0x05,
    gt3 = 0x06,
    pace_car = 0x08,
    unknown = 0xff,
    _,
};

pub const VehicleChampionship = enum(u8) {
    wec_2023 = 0x00,
    wec_2024 = 0x01,
    wec_2025 = 0x02,
    wec_2026 = 0x03,
    elms_2025 = 0x10,
    elms_2026 = 0x11,
    unknown = 0xff,
    _,
};

pub const FinishStatus = enum(i8) {
    none = 0,
    finished = 1,
    dnf = 2,
    dq = 3,
    _,
};

pub const Control = enum(i8) {
    nobody = -1,
    local_player = 0,
    local_ai = 1,
    remote = 2,
    replay = 3,
    _,
};

pub const PitState = enum(u8) {
    none = 0,
    request = 1,
    entering = 2,
    stopped = 3,
    exiting = 4,
    _,

    pub fn label(self: PitState) []const u8 {
        return switch (self) {
            .none => "Track",
            .request => "Pit Request",
            .entering => "Pit Entry",
            .stopped => "Pit Box",
            .exiting => "Pit Exit",
            _ => "?",
        };
    }
};

pub const SharedMemoryEvent = enum(u32) {
    enter = 0,
    exit = 1,
    startup = 2,
    shutdown = 3,
    load = 4,
    unload = 5,
    start_session = 6,
    end_session = 7,
    enter_realtime = 8,
    exit_realtime = 9,
    update_scoring = 10,
    update_telemetry = 11,
    init_application = 12,
    uninit_application = 13,
    set_environment = 14,
    ffb = 15,
};

pub const shared_memory_event_count = 16;

pub const TelemVect3 = extern struct {
    x: f64 align(4) = 0,
    y: f64 align(4) = 0,
    z: f64 align(4) = 0,
};

pub const TelemWheelV01 = extern struct {
    suspension_deflection: f64 align(4) = 0,
    ride_height: f64 align(4) = 0,
    susp_force: f64 align(4) = 0,
    brake_temp: f64 align(4) = 0,
    brake_pressure: f64 align(4) = 0,
    rotation: f64 align(4) = 0,
    lateral_patch_vel: f64 align(4) = 0,
    longitudinal_patch_vel: f64 align(4) = 0,
    lateral_ground_vel: f64 align(4) = 0,
    longitudinal_ground_vel: f64 align(4) = 0,
    camber: f64 align(4) = 0,
    lateral_force: f64 align(4) = 0,
    longitudinal_force: f64 align(4) = 0,
    tire_load: f64 align(4) = 0,
    grip_fract: f64 align(4) = 0,
    pressure: f64 align(4) = 0,
    temperature: [3]f64 align(4) = .{ 0, 0, 0 },
    wear: f64 align(4) = 0,
    terrain_name: [16]u8 = @splat(0),
    surface_type: u8 = 0,
    flat: bool = false,
    detached: bool = false,
    static_undeflected_radius: u8 = 0,
    vertical_tire_deflection: f64 align(4) = 0,
    wheel_y_location: f64 align(4) = 0,
    toe: f64 align(4) = 0,
    tire_carcass_temperature: f64 align(4) = 0,
    tire_inner_layer_temperature: [3]f64 align(4) = .{ 0, 0, 0 },
    optimal_temp: f32 = 0,
    compound_index: u8 = 0,
    compound_type: u8 = 0,
    expansion: [18]u8 = @splat(0),
};

pub const TelemInfoV01 = extern struct {
    id: i32 = 0,
    delta_time: f64 align(4) = 0,
    elapsed_time: f64 align(4) = 0,
    lap_number: i32 = 0,
    lap_start_et: f64 align(4) = 0,
    vehicle_name: [64]u8 = @splat(0),
    track_name: [64]u8 = @splat(0),

    pos: TelemVect3 = .{},
    local_vel: TelemVect3 = .{},
    local_accel: TelemVect3 = .{},

    ori: [3]TelemVect3 = @splat(.{}),
    local_rot: TelemVect3 = .{},
    local_rot_accel: TelemVect3 = .{},

    gear: i32 = 0,
    engine_rpm: f64 align(4) = 0,
    engine_water_temp: f64 align(4) = 0,
    engine_oil_temp: f64 align(4) = 0,
    clutch_rpm: f64 align(4) = 0,

    unfiltered_throttle: f64 align(4) = 0,
    unfiltered_brake: f64 align(4) = 0,
    unfiltered_steering: f64 align(4) = 0,
    unfiltered_clutch: f64 align(4) = 0,
    filtered_throttle: f64 align(4) = 0,
    filtered_brake: f64 align(4) = 0,
    filtered_steering: f64 align(4) = 0,
    filtered_clutch: f64 align(4) = 0,

    steering_shaft_torque: f64 align(4) = 0,
    front_3rd_deflection: f64 align(4) = 0,
    rear_3rd_deflection: f64 align(4) = 0,

    front_wing_height: f64 align(4) = 0,
    front_ride_height: f64 align(4) = 0,
    rear_ride_height: f64 align(4) = 0,
    drag: f64 align(4) = 0,
    front_downforce: f64 align(4) = 0,
    rear_downforce: f64 align(4) = 0,

    fuel: f64 align(4) = 0,
    engine_max_rpm: f64 align(4) = 0,
    scheduled_stops: u8 = 0,
    overheating: bool = false,
    detached: bool = false,
    headlights: bool = false,
    dent_severity: [8]u8 = @splat(0),
    last_impact_et: f64 align(4) = 0,
    last_impact_magnitude: f64 align(4) = 0,
    last_impact_pos: TelemVect3 = .{},

    engine_torque: f64 align(4) = 0,
    current_sector: i32 = 0,
    speed_limiter: u8 = 0,
    max_gears: u8 = 0,
    front_tire_compound_index: u8 = 0,
    rear_tire_compound_index: u8 = 0,
    fuel_capacity: f64 align(4) = 0,
    front_flap_activated: u8 = 0,
    rear_flap_activated: u8 = 0,
    rear_flap_legal_status: u8 = 0,
    ignition_starter: u8 = 0,
    front_tire_compound_name: [18]u8 = @splat(0),
    rear_tire_compound_name: [18]u8 = @splat(0),
    speed_limiter_available: u8 = 0,
    anti_stall_activated: u8 = 0,
    unused: [2]u8 = @splat(0),
    visual_steering_wheel_range: f32 = 0,
    rear_brake_bias: f64 align(4) = 0,
    turbo_boost_pressure: f64 align(4) = 0,
    physics_to_graphics_offset: [3]f32 = .{ 0, 0, 0 },
    physical_steering_wheel_range: f32 = 0,
    delta_best: f64 align(4) = 0,
    battery_charge_fraction: f64 align(4) = 0,

    electric_boost_motor_torque: f64 align(4) = 0,
    electric_boost_motor_rpm: f64 align(4) = 0,
    electric_boost_motor_temperature: f64 align(4) = 0,
    electric_boost_water_temperature: f64 align(4) = 0,
    electric_boost_motor_state: u8 = 0,
    lap_invalidated: bool = false,
    abs_active: bool = false,
    tc_active: bool = false,
    speed_limiter_active: bool = false,
    wiper_state: u8 = 0,
    tc: u8 = 0,
    tc_max: u8 = 0,
    tc_slip: u8 = 0,
    tc_slip_max: u8 = 0,
    tc_cut: u8 = 0,
    tc_cut_max: u8 = 0,
    abs: u8 = 0,
    abs_max: u8 = 0,
    motor_map: u8 = 0,
    motor_map_max: u8 = 0,
    migration: u8 = 0,
    migration_max: u8 = 0,
    front_anti_sway: u8 = 0,
    front_anti_sway_max: u8 = 0,
    rear_anti_sway: u8 = 0,
    rear_anti_sway_max: u8 = 0,
    lift_and_coast_progress: u8 = 0,
    track_limits_steps: u8 = 0,
    regen: f32 = 0,
    soc: f32 = 0,
    virtual_energy: f32 = 0,
    time_gap_car_ahead: f32 = 0,
    time_gap_car_behind: f32 = 0,
    time_gap_place_ahead: f32 = 0,
    time_gap_place_behind: f32 = 0,
    vehicle_model: [30]u8 = @splat(0),
    vehicle_class: VehicleClass = .unknown,
    vehicle_championship: VehicleChampionship = .unknown,
    expansion: [20]u8 = @splat(0),
    wheel: [4]TelemWheelV01 = @splat(.{}),

    pub fn speedKmh(self: *const TelemInfoV01) f64 {
        const v = self.local_vel;
        return @sqrt(v.x * v.x + v.y * v.y + v.z * v.z) * 3.6;
    }
};

pub const VehicleScoringInfoV01 = extern struct {
    id: i32 = 0,
    driver_name: [32]u8 = @splat(0),
    vehicle_name: [64]u8 = @splat(0),
    total_laps: i16 = 0,
    sector: i8 = 0,
    finish_status: FinishStatus = .none,
    lap_dist: f64 align(4) = 0,
    path_lateral: f64 align(4) = 0,
    track_edge: f64 align(4) = 0,
    best_sector1: f64 align(4) = 0,
    best_sector2: f64 align(4) = 0,
    best_lap_time: f64 align(4) = 0,
    last_sector1: f64 align(4) = 0,
    last_sector2: f64 align(4) = 0,
    last_lap_time: f64 align(4) = 0,
    cur_sector1: f64 align(4) = 0,
    cur_sector2: f64 align(4) = 0,
    num_pitstops: i16 = 0,
    num_penalties: i16 = 0,
    is_player: bool = false,
    control: Control = .nobody,
    in_pits: bool = false,
    place: u8 = 0,
    vehicle_class: [32]u8 = @splat(0),
    time_behind_next: f64 align(4) = 0,
    laps_behind_next: i32 = 0,
    time_behind_leader: f64 align(4) = 0,
    laps_behind_leader: i32 = 0,
    lap_start_et: f64 align(4) = 0,
    pos: TelemVect3 = .{},
    local_vel: TelemVect3 = .{},
    local_accel: TelemVect3 = .{},
    ori: [3]TelemVect3 = @splat(.{}),
    local_rot: TelemVect3 = .{},
    local_rot_accel: TelemVect3 = .{},
    headlights: u8 = 0,
    pit_state: PitState = .none,
    server_scored: u8 = 0,
    individual_phase: u8 = 0,
    qualification: i32 = 0,
    time_into_lap: f64 align(4) = 0,
    estimated_lap_time: f64 align(4) = 0,
    pit_group: [24]u8 = @splat(0),
    flag: u8 = 0,
    under_yellow: bool = false,
    count_lap_flag: u8 = 0,
    in_garage_stall: bool = false,
    upgrade_pack: [16]u8 = @splat(0),
    pit_lap_dist: f32 = 0,
    best_lap_sector1: f32 = 0,
    best_lap_sector2: f32 = 0,
    steam_id: u64 align(4) = 0,
    veh_filename: [32]u8 = @splat(0),
    attack_mode: i16 = 0,
    fuel_fraction: u8 = 0,
    drs_state: bool = false,
    expansion: [4]u8 = @splat(0),

    pub fn pitStateValue(self: *const VehicleScoringInfoV01) PitState {
        return self.pit_state;
    }
};

pub const ScoringInfoV01 = extern struct {
    track_name: [64]u8 = @splat(0),
    session: SessionType = .test_day,
    current_et: f64 align(4) = 0,
    end_et: f64 align(4) = 0,
    max_laps: i32 = 0,
    lap_dist: f64 align(4) = 0,
    results_stream: usize align(4) = 0,
    num_vehicles: i32 = 0,
    game_phase: GamePhase = .before_session,
    yellow_flag_state: i8 = -1,
    sector_flag: [3]i8 = @splat(0),
    start_light: u8 = 0,
    num_red_lights: u8 = 0,
    in_realtime: bool = false,
    player_name: [32]u8 = @splat(0),
    plr_file_name: [64]u8 = @splat(0),
    dark_cloud: f64 align(4) = 0,
    raining: f64 align(4) = 0,
    ambient_temp: f64 align(4) = 0,
    track_temp: f64 align(4) = 0,
    wind: TelemVect3 = .{},
    min_path_wetness: f64 align(4) = 0,
    max_path_wetness: f64 align(4) = 0,
    game_mode: u8 = 0,
    is_password_protected: bool = false,
    server_port: u16 = 0,
    server_public_ip: u32 = 0,
    max_players: i32 = 0,
    server_name: [32]u8 = @splat(0),
    start_et: f32 = 0,
    avg_path_wetness: f64 align(4) = 0,
    session_time_remaining: f32 = 0,
    time_of_day: f32 = 0,
    is_fixed_setup: bool = false,
    track_grip_level: u8 = 0,
    cloud_coverage: u8 = 0,
    track_limits_steps_per_penalty: u8 = 0,
    track_limits_steps_per_point: u8 = 0,
    expansion: [187]u8 = @splat(0),
    vehicle: usize align(4) = 0,

    pub fn sessionValue(self: *const ScoringInfoV01) SessionType {
        return self.session;
    }

    pub fn gamePhaseValue(self: *const ScoringInfoV01) GamePhase {
        return self.game_phase;
    }
};

pub const ApplicationStateV01 = extern struct {
    app_window: usize align(4) = 0,
    width: u32 = 0,
    height: u32 = 0,
    refresh_rate: u32 = 0,
    windowed: u32 = 0,
    options_location: u8 = 0,
    options_page: [31]u8 = @splat(0),
    expansion: [204]u8 = @splat(0),
};

pub const SharedMemoryGeneric = extern struct {
    events: [shared_memory_event_count]u32 = @splat(0),
    game_version: i32 = 0,
    ffb_torque: f32 = 0,
    app_info: ApplicationStateV01 = .{},
};

pub const SharedMemoryPathData = extern struct {
    user_data: [max_path]u8 = @splat(0),
    custom_variables: [max_path]u8 = @splat(0),
    steward_results: [max_path]u8 = @splat(0),
    player_profile: [max_path]u8 = @splat(0),
    plugins_folder: [max_path]u8 = @splat(0),
};

pub const SharedMemoryScoringData = extern struct {
    scoring_info: ScoringInfoV01 = .{},
    scoring_stream_size: usize = 0,
    veh_scoring_info: [max_vehicles]VehicleScoringInfoV01 = @splat(.{}),
    scoring_stream: [scoring_stream_size]u8 = @splat(0),
};

pub const SharedMemoryTelemetryData = extern struct {
    active_vehicles: u8 = 0,
    player_vehicle_idx: u8 = 0,
    player_has_vehicle: bool = false,
    _pad0: u8 = 0,
    telem_info: [max_vehicles]TelemInfoV01 = @splat(.{}),
};

pub const SharedMemoryObjectOut = extern struct {
    generic: SharedMemoryGeneric = .{},
    paths: SharedMemoryPathData = .{},
    scoring: SharedMemoryScoringData = .{},
    telemetry: SharedMemoryTelemetryData = .{},
};

pub const SharedMemoryLayout = extern struct {
    data: SharedMemoryObjectOut = .{},
};

pub const telemetry_offset = @offsetOf(SharedMemoryObjectOut, "telemetry");
pub const telemetry_info_offset = telemetry_offset + @offsetOf(SharedMemoryTelemetryData, "telem_info");
pub const scoring_offset = @offsetOf(SharedMemoryObjectOut, "scoring");
pub const scoring_info_offset = scoring_offset + @offsetOf(SharedMemoryScoringData, "scoring_info");
pub const vehicle_scoring_offset = scoring_offset + @offsetOf(SharedMemoryScoringData, "veh_scoring_info");

pub fn cstr(buf: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
    return buf[0..end];
}

pub fn cstrToUtf8(src_bytes: []const u8, out: []u8) ?[]const u8 {
    const s = cstr(src_bytes);
    if (!std.unicode.utf8ValidateSlice(s)) return null;
    const len = @min(s.len, out.len);
    @memcpy(out[0..len], s[0..len]);
    return out[0..len];
}

pub fn readActiveVehicles(view: []const u8) ?u8 {
    const offset = telemetry_offset + @offsetOf(SharedMemoryTelemetryData, "active_vehicles");
    if (view.len <= offset) return null;
    return view[offset];
}

pub fn readPlayerVehicleIdx(view: []const u8) ?u8 {
    const offset = telemetry_offset + @offsetOf(SharedMemoryTelemetryData, "player_vehicle_idx");
    if (view.len <= offset) return null;
    return view[offset];
}

pub fn readPlayerHasVehicle(view: []const u8) ?bool {
    const offset = telemetry_offset + @offsetOf(SharedMemoryTelemetryData, "player_has_vehicle");
    if (view.len <= offset) return null;
    return view[offset] != 0;
}

test "native LMU layout matches shipped C++ headers" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TelemVect3));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(TelemVect3));
    try std.testing.expectEqual(@as(usize, 260), @sizeOf(TelemWheelV01));
    try std.testing.expectEqual(@as(usize, 1888), @sizeOf(TelemInfoV01));
    try std.testing.expectEqual(@as(usize, 584), @sizeOf(VehicleScoringInfoV01));
    try std.testing.expectEqual(@as(usize, 548), @sizeOf(ScoringInfoV01));
    try std.testing.expectEqual(@as(usize, 260), @sizeOf(ApplicationStateV01));
    try std.testing.expectEqual(@as(usize, 332), @sizeOf(SharedMemoryGeneric));
    try std.testing.expectEqual(@as(usize, 1300), @sizeOf(SharedMemoryPathData));
    try std.testing.expectEqual(@as(usize, 126832), @sizeOf(SharedMemoryScoringData));
    try std.testing.expectEqual(@as(usize, 196356), @sizeOf(SharedMemoryTelemetryData));
    try std.testing.expectEqual(@as(usize, 324824), @sizeOf(SharedMemoryObjectOut));
    try std.testing.expectEqual(@as(usize, 324824), @sizeOf(SharedMemoryLayout));

    try std.testing.expectEqual(@as(usize, 352), @offsetOf(TelemInfoV01, "gear"));
    try std.testing.expectEqual(@as(usize, 356), @offsetOf(TelemInfoV01, "engine_rpm"));
    try std.testing.expectEqual(@as(usize, 524), @offsetOf(TelemInfoV01, "fuel"));
    try std.testing.expectEqual(@as(usize, 696), @offsetOf(TelemInfoV01, "delta_best"));
    try std.testing.expectEqual(@as(usize, 744), @offsetOf(TelemInfoV01, "electric_boost_motor_state"));
    try std.testing.expectEqual(@as(usize, 768), @offsetOf(TelemInfoV01, "regen"));
    try std.testing.expectEqual(@as(usize, 848), @offsetOf(TelemInfoV01, "wheel"));

    try std.testing.expectEqual(@as(usize, 104), @offsetOf(VehicleScoringInfoV01, "lap_dist"));
    try std.testing.expectEqual(@as(usize, 144), @offsetOf(VehicleScoringInfoV01, "best_lap_time"));
    try std.testing.expectEqual(@as(usize, 196), @offsetOf(VehicleScoringInfoV01, "is_player"));
    try std.testing.expectEqual(@as(usize, 536), @offsetOf(VehicleScoringInfoV01, "steam_id"));
    try std.testing.expectEqual(@as(usize, 578), @offsetOf(VehicleScoringInfoV01, "fuel_fraction"));

    try std.testing.expectEqual(@as(usize, 96), @offsetOf(ScoringInfoV01, "results_stream"));
    try std.testing.expectEqual(@as(usize, 212), @offsetOf(ScoringInfoV01, "dark_cloud"));
    try std.testing.expectEqual(@as(usize, 340), @offsetOf(ScoringInfoV01, "session_time_remaining"));
    try std.testing.expectEqual(@as(usize, 540), @offsetOf(ScoringInfoV01, "vehicle"));

    try std.testing.expectEqual(@as(usize, 128464), telemetry_offset);
    try std.testing.expectEqual(@as(usize, 128468), telemetry_info_offset);
    try std.testing.expectEqual(@as(usize, 1632), scoring_offset);
    try std.testing.expectEqual(@as(usize, 1632), scoring_info_offset);
    try std.testing.expectEqual(@as(usize, 2192), vehicle_scoring_offset);
}

test "cstr helpers stop at NUL and validate UTF-8" {
    const src = [_]u8{ 'S', 'p', 'a', 0, 'X' };
    try std.testing.expectEqualStrings("Spa", cstr(&src));
    var out: [16]u8 = undefined;
    try std.testing.expectEqualStrings("Spa", cstrToUtf8(&src, &out).?);
}
