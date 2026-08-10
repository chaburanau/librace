//! RaceRoom Racing Experience (`$R3E`) shared-memory layout.
//!
//! Reference: official [sector3studios/r3e-api](https://github.com/sector3studios/r3e-api)
//! `sample-c/src/r3e.h` (shared API major 3 / minor 5).
//!
//! Layout notes:
//! - Single named mapping `"$R3E"` with `#pragma pack(1)` C structs (no padding).
//! - Strings are UTF-8 (`r3e_u8char` buffers).
//! - `all_drivers` is large (128 × driver rows); the client copies only the core prefix on
//!   the hot poll path and loads driver rows on demand.
//! - Speeds are m/s; engine speed is rad/s (`engine_rps`).

const std = @import("std");
const strings = @import("../../core/utils/strings.zig");

pub const mem_map_name = "$R3E";

pub const version_major: i32 = 3;
pub const version_minor: i32 = 5;
pub const num_drivers_max: usize = 128;
pub const tire_index_max: usize = 4;
pub const tire_temp_index_max: usize = 3;
pub const pit_menu_max: usize = 12;

pub const shared_size: usize = 43996;
pub const player_data_size: usize = 560;
pub const driver_data_size: usize = 328;
pub const driver_info_size: usize = 128;
/// Bytes from the start of `Shared` through `num_cars` (excludes `all_drivers`).
pub const shared_core_size: usize = 2012;

pub const rps_to_rpm: f32 = 60.0 / (2.0 * std.math.pi);
pub const mps_to_kmh: f32 = 3.6;

pub const GameMode = enum(i32) {
    unavailable = -1,
    track_test = 0,
    leaderboard_challenge = 1,
    competition = 2,
    single_race = 3,
    championship = 4,
    multiplayer = 5,
    multiplayer_ranked = 6,
    try_before_you_buy = 7,
    _,

    pub fn label(self: GameMode) []const u8 {
        return switch (self) {
            .unavailable => "—",
            .track_test => "Track Test",
            .leaderboard_challenge => "Leaderboard",
            .competition => "Competition",
            .single_race => "Single Race",
            .championship => "Championship",
            .multiplayer => "Multiplayer",
            .multiplayer_ranked => "Ranked MP",
            .try_before_you_buy => "TBYB",
            _ => "?",
        };
    }
};

pub const SessionType = enum(i32) {
    unavailable = -1,
    practice = 0,
    qualify = 1,
    race = 2,
    warmup = 3,
    _,

    pub fn label(self: SessionType) []const u8 {
        return switch (self) {
            .unavailable => "—",
            .practice => "Practice",
            .qualify => "Qualify",
            .race => "Race",
            .warmup => "Warmup",
            _ => "?",
        };
    }
};

pub const SessionPhase = enum(i32) {
    unavailable = -1,
    garage = 1,
    gridwalk = 2,
    formation = 3,
    countdown = 4,
    green = 5,
    checkered = 6,
    _,

    pub fn label(self: SessionPhase) []const u8 {
        return switch (self) {
            .unavailable => "—",
            .garage => "Garage",
            .gridwalk => "Gridwalk",
            .formation => "Formation",
            .countdown => "Countdown",
            .green => "Green",
            .checkered => "Checkered",
            _ => "?",
        };
    }
};

pub const Control = enum(i32) {
    unavailable = -1,
    player = 0,
    ai = 1,
    remote = 2,
    replay = 3,
    _,
};

pub const PitWindow = enum(i32) {
    unavailable = -1,
    disabled = 0,
    closed = 1,
    open = 2,
    stopped = 3,
    completed = 4,
    _,
};

pub const PitMenuSelection = enum(i32) {
    unavailable = -1,
    preset = 0,
    penalty = 1,
    driver_change = 2,
    fuel = 3,
    front_tires = 4,
    rear_tires = 5,
    body = 6,
    front_wing = 7,
    rear_wing = 8,
    suspension = 9,
    button_top = 10,
    button_bottom = 11,
    max = 12,
    _,
};

pub const TireType = enum(i32) {
    unavailable = -1,
    option = 0,
    prime = 1,
    _,
};

pub const TireSubtype = enum(i32) {
    unavailable = -1,
    primary = 0,
    alternate = 1,
    soft = 2,
    medium = 3,
    hard = 4,
    _,
};

pub const MaterialType = enum(i32) {
    unavailable = -1,
    none = 0,
    tarmac = 1,
    grass = 2,
    dirt = 3,
    gravel = 4,
    rumble = 5,
    concrete = 6,
    _,
};

pub const PitstopStatus = enum(i32) {
    unavailable = -1,
    two_tyres_unserved = 0,
    four_tyres_unserved = 1,
    served = 2,
    _,
};

pub const FinishStatus = enum(i32) {
    unavailable = -1,
    none = 0,
    finished = 1,
    dnf = 2,
    dnq = 3,
    dns = 4,
    dq = 5,
    _,
};

pub const SessionLengthFormat = enum(i32) {
    unavailable = -1,
    time_based = 0,
    lap_based = 1,
    time_and_lap_based = 2,
    _,
};

pub const EngineType = enum(i32) {
    combustion = 0,
    electric = 1,
    hybrid = 2,
    _,
};

pub const Vec3F32 = extern struct {
    x: f32 align(1) = 0,
    y: f32 align(1) = 0,
    z: f32 align(1) = 0,
};

pub const Vec3F64 = extern struct {
    x: f64 align(1) = 0,
    y: f64 align(1) = 0,
    z: f64 align(1) = 0,
};

pub const OriF32 = extern struct {
    pitch: f32 align(1) = 0,
    yaw: f32 align(1) = 0,
    roll: f32 align(1) = 0,
};

pub const SectorStarts = extern struct {
    sector1: f32 align(1) = 0,
    sector2: f32 align(1) = 0,
    sector3: f32 align(1) = 0,
};

pub const PlayerData = extern struct {
    user_id: i32 align(1) = 0,
    game_simulation_ticks: i32 align(1) = 0,
    game_simulation_time: f64 align(1) = 0,
    position: Vec3F64 align(1) = .{},
    velocity: Vec3F64 align(1) = .{},
    local_velocity: Vec3F64 align(1) = .{},
    acceleration: Vec3F64 align(1) = .{},
    local_acceleration: Vec3F64 align(1) = .{},
    orientation: Vec3F64 align(1) = .{},
    rotation: Vec3F64 align(1) = .{},
    angular_acceleration: Vec3F64 align(1) = .{},
    angular_velocity: Vec3F64 align(1) = .{},
    local_angular_velocity: Vec3F64 align(1) = .{},
    local_g_force: Vec3F64 align(1) = .{},
    steering_force: f64 align(1) = 0,
    steering_force_percentage: f64 align(1) = 0,
    engine_torque: f64 align(1) = 0,
    current_downforce: f64 align(1) = 0,
    voltage: f64 align(1) = 0,
    ers_level: f64 align(1) = 0,
    power_mgu_h: f64 align(1) = 0,
    power_mgu_k: f64 align(1) = 0,
    torque_mgu_k: f64 align(1) = 0,
    suspension_deflection: [tire_index_max]f64 align(1) = @splat(0),
    suspension_velocity: [tire_index_max]f64 align(1) = @splat(0),
    camber: [tire_index_max]f64 align(1) = @splat(0),
    ride_height: [tire_index_max]f64 align(1) = @splat(0),
    front_wing_height: f64 align(1) = 0,
    front_roll_angle: f64 align(1) = 0,
    rear_roll_angle: f64 align(1) = 0,
    third_spring_suspension_deflection_front: f64 align(1) = 0,
    third_spring_suspension_velocity_front: f64 align(1) = 0,
    third_spring_suspension_deflection_rear: f64 align(1) = 0,
    third_spring_suspension_velocity_rear: f64 align(1) = 0,
    unused1: f64 align(1) = 0,
    unused2: f64 align(1) = 0,
    unused3: f64 align(1) = 0,
};

pub const Flags = extern struct {
    yellow: i32 align(1) = 0,
    yellow_caused_it: i32 align(1) = 0,
    yellow_overtake: i32 align(1) = 0,
    yellow_positions_gained: i32 align(1) = 0,
    sector_yellow: [3]i32 align(1) = @splat(0),
    closest_yellow_distance_into_track: f32 align(1) = 0,
    blue: i32 align(1) = 0,
    black: i32 align(1) = 0,
    green: i32 align(1) = 0,
    checkered: i32 align(1) = 0,
    white: i32 align(1) = 0,
    black_and_white: i32 align(1) = 0,
};

pub const CarDamage = extern struct {
    engine: f32 align(1) = 0,
    transmission: f32 align(1) = 0,
    aerodynamics: f32 align(1) = 0,
    suspension: f32 align(1) = 0,
    unused1: f32 align(1) = 0,
    unused2: f32 align(1) = 0,
};

pub const CutTrackPenalties = extern struct {
    drive_through: f32 align(1) = 0,
    stop_and_go: f32 align(1) = 0,
    pit_stop: f32 align(1) = 0,
    time_deduction: f32 align(1) = 0,
    slow_down: f32 align(1) = 0,
};

pub const Drs = extern struct {
    equipped: i32 align(1) = 0,
    available: i32 align(1) = 0,
    num_activations_left: i32 align(1) = 0,
    engaged: i32 align(1) = 0,
};

pub const PushToPass = extern struct {
    available: i32 align(1) = 0,
    engaged: i32 align(1) = 0,
    amount_left: i32 align(1) = 0,
    engaged_time_left: f32 align(1) = 0,
    wait_time_left: f32 align(1) = 0,
};

pub const TireTemp = extern struct {
    current_temp: [tire_temp_index_max]f32 align(1) = @splat(0),
    optimal_temp: f32 align(1) = 0,
    cold_temp: f32 align(1) = 0,
    hot_temp: f32 align(1) = 0,
};

pub const BrakeTemp = extern struct {
    current_temp: f32 align(1) = 0,
    optimal_temp: f32 align(1) = 0,
    cold_temp: f32 align(1) = 0,
    hot_temp: f32 align(1) = 0,
};

pub const AidSettings = extern struct {
    abs: i32 align(1) = 0,
    tc: i32 align(1) = 0,
    esp: i32 align(1) = 0,
    countersteer: i32 align(1) = 0,
    cornering: i32 align(1) = 0,
};

pub const DriverInfo = extern struct {
    name: [64]u8 align(1) = @splat(0),
    car_number: i32 align(1) = 0,
    class_id: i32 align(1) = 0,
    model_id: i32 align(1) = 0,
    team_id: i32 align(1) = 0,
    livery_id: i32 align(1) = 0,
    manufacturer_id: i32 align(1) = 0,
    user_id: i32 align(1) = 0,
    slot_id: i32 align(1) = 0,
    class_performance_index: i32 align(1) = 0,
    engine_type: i32 align(1) = 0,
    car_width: f32 align(1) = 0,
    car_length: f32 align(1) = 0,
    rating: f32 align(1) = 0,
    reputation: f32 align(1) = 0,
    unused1: f32 align(1) = 0,
    unused2: f32 align(1) = 0,

    pub fn nameUtf8(self: *const DriverInfo) []const u8 {
        return strings.cString(&self.name);
    }

    pub fn engineTypeValue(self: *const DriverInfo) EngineType {
        return @enumFromInt(self.engine_type);
    }
};

pub const DriverData = extern struct {
    driver_info: DriverInfo align(1) = .{},
    finish_status: i32 align(1) = 0,
    place: i32 align(1) = 0,
    place_class: i32 align(1) = 0,
    lap_distance: f32 align(1) = 0,
    lap_distance_fraction: f32 align(1) = 0,
    position: Vec3F32 align(1) = .{},
    track_sector: i32 align(1) = 0,
    completed_laps: i32 align(1) = 0,
    current_lap_valid: i32 align(1) = 0,
    lap_time_current_self: f32 align(1) = 0,
    sector_time_current_self: [3]f32 align(1) = @splat(0),
    sector_time_previous_self: [3]f32 align(1) = @splat(0),
    sector_time_best_self: [3]f32 align(1) = @splat(0),
    time_delta_front: f32 align(1) = 0,
    time_delta_behind: f32 align(1) = 0,
    pitstop_status: i32 align(1) = 0,
    in_pitlane: i32 align(1) = 0,
    num_pitstops: i32 align(1) = 0,
    penalties: CutTrackPenalties align(1) = .{},
    car_speed: f32 align(1) = 0,
    tire_type_front: i32 align(1) = 0,
    tire_type_rear: i32 align(1) = 0,
    tire_subtype_front: i32 align(1) = 0,
    tire_subtype_rear: i32 align(1) = 0,
    base_penalty_weight: f32 align(1) = 0,
    aid_penalty_weight: f32 align(1) = 0,
    drs_state: i32 align(1) = 0,
    ptp_state: i32 align(1) = 0,
    virtual_energy: f32 align(1) = 0,
    penalty_type: i32 align(1) = 0,
    penalty_reason: i32 align(1) = 0,
    engine_state: i32 align(1) = 0,
    orientation: Vec3F32 align(1) = .{},
    unused1: f32 align(1) = 0,
    unused2: f32 align(1) = 0,
    unused3: f32 align(1) = 0,

    pub fn finishStatusValue(self: *const DriverData) FinishStatus {
        return @enumFromInt(self.finish_status);
    }

    pub fn pitstopStatusValue(self: *const DriverData) PitstopStatus {
        return @enumFromInt(self.pitstop_status);
    }

    pub fn speedKmh(self: *const DriverData) f32 {
        return self.car_speed * mps_to_kmh;
    }
};

/// Full `$R3E` mapping. Prefer `shared()` (core) on the hot path; use `drivers()` for the array.
pub const Shared = extern struct {
    version_major: i32 align(1) = 0,
    version_minor: i32 align(1) = 0,
    all_drivers_offset: i32 align(1) = 0,
    driver_data_size: i32 align(1) = 0,

    game_mode: i32 align(1) = 0,
    game_paused: i32 align(1) = 0,
    game_in_menus: i32 align(1) = 0,
    game_in_replay: i32 align(1) = 0,
    game_using_vr: i32 align(1) = 0,
    game_player_in_garage: i32 align(1) = 0,

    player: PlayerData align(1) = .{},

    track_name: [64]u8 align(1) = @splat(0),
    layout_name: [64]u8 align(1) = @splat(0),
    track_id: i32 align(1) = 0,
    layout_id: i32 align(1) = 0,
    layout_length: f32 align(1) = 0,
    sector_start_factors: SectorStarts align(1) = .{},
    race_session_laps: [3]i32 align(1) = @splat(0),
    race_session_minutes: [3]i32 align(1) = @splat(0),
    event_index: i32 align(1) = 0,
    session_type: i32 align(1) = 0,
    session_iteration: i32 align(1) = 0,
    session_length_format: i32 align(1) = 0,
    session_pit_speed_limit: f32 align(1) = 0,
    session_phase: i32 align(1) = 0,
    start_lights: i32 align(1) = 0,
    tire_wear_active: i32 align(1) = 0,
    fuel_use_active: i32 align(1) = 0,
    number_of_laps: i32 align(1) = 0,
    session_time_duration: f32 align(1) = 0,
    session_time_remaining: f32 align(1) = 0,
    max_incident_points: i32 align(1) = 0,
    event_unused1: f32 align(1) = 0,
    event_unused2: f32 align(1) = 0,

    pit_window_status: i32 align(1) = 0,
    pit_window_start: i32 align(1) = 0,
    pit_window_end: i32 align(1) = 0,
    in_pitlane: i32 align(1) = 0,
    pit_menu_selection: i32 align(1) = 0,
    pit_menu_state: [pit_menu_max]i32 align(1) = @splat(0),
    pit_state: i32 align(1) = 0,
    pit_total_duration: f32 align(1) = 0,
    pit_elapsed_time: f32 align(1) = 0,
    pit_action: i32 align(1) = 0,
    num_pitstops: i32 align(1) = 0,
    pit_min_duration_total: f32 align(1) = 0,
    pit_min_duration_left: f32 align(1) = 0,

    flags: Flags align(1) = .{},
    position: i32 align(1) = 0,
    position_class: i32 align(1) = 0,
    finish_status: i32 align(1) = 0,
    cut_track_warnings: i32 align(1) = 0,
    penalties: CutTrackPenalties align(1) = .{},
    num_penalties: i32 align(1) = 0,
    completed_laps: i32 align(1) = 0,
    current_lap_valid: i32 align(1) = 0,
    track_sector: i32 align(1) = 0,
    lap_distance: f32 align(1) = 0,
    lap_distance_fraction: f32 align(1) = 0,
    lap_time_best_leader: f32 align(1) = 0,
    lap_time_best_leader_class: f32 align(1) = 0,
    session_best_lap_sector_times: [3]f32 align(1) = @splat(0),
    lap_time_best_self: f32 align(1) = 0,
    sector_time_best_self: [3]f32 align(1) = @splat(0),
    lap_time_previous_self: f32 align(1) = 0,
    sector_time_previous_self: [3]f32 align(1) = @splat(0),
    lap_time_current_self: f32 align(1) = 0,
    sector_time_current_self: [3]f32 align(1) = @splat(0),
    lap_time_delta_leader: f32 align(1) = 0,
    lap_time_delta_leader_class: f32 align(1) = 0,
    time_delta_front: f32 align(1) = 0,
    time_delta_behind: f32 align(1) = 0,
    time_delta_best_self: f32 align(1) = 0,
    best_individual_sector_time_self: [3]f32 align(1) = @splat(0),
    best_individual_sector_time_leader: [3]f32 align(1) = @splat(0),
    best_individual_sector_time_leader_class: [3]f32 align(1) = @splat(0),
    incident_points: i32 align(1) = 0,
    lap_valid_state: i32 align(1) = 0,
    prev_lap_valid: i32 align(1) = 0,
    discharge_rate: f32 align(1) = 0,
    brake_regen: f32 align(1) = 0,
    unused1: f32 align(1) = 0,

    vehicle_info: DriverInfo align(1) = .{},
    player_name: [64]u8 align(1) = @splat(0),

    control_type: i32 align(1) = 0,
    car_speed: f32 align(1) = 0,
    engine_rps: f32 align(1) = 0,
    max_engine_rps: f32 align(1) = 0,
    upshift_rps: f32 align(1) = 0,
    gear: i32 align(1) = 0,
    num_gears: i32 align(1) = 0,
    car_cg_location: Vec3F32 align(1) = .{},
    car_orientation: OriF32 align(1) = .{},
    local_acceleration: Vec3F32 align(1) = .{},
    total_mass: f32 align(1) = 0,
    fuel_left: f32 align(1) = 0,
    fuel_capacity: f32 align(1) = 0,
    fuel_per_lap: f32 align(1) = 0,
    virtual_energy_left: f32 align(1) = 0,
    virtual_energy_capacity: f32 align(1) = 0,
    virtual_energy_per_lap: f32 align(1) = 0,
    engine_temp: f32 align(1) = 0,
    engine_oil_temp: f32 align(1) = 0,
    fuel_pressure: f32 align(1) = 0,
    engine_oil_pressure: f32 align(1) = 0,
    turbo_pressure: f32 align(1) = 0,
    throttle: f32 align(1) = 0,
    throttle_raw: f32 align(1) = 0,
    brake: f32 align(1) = 0,
    brake_raw: f32 align(1) = 0,
    clutch: f32 align(1) = 0,
    clutch_raw: f32 align(1) = 0,
    steer_input_raw: f32 align(1) = 0,
    steer_lock_degrees: i32 align(1) = 0,
    steer_wheel_range_degrees: i32 align(1) = 0,
    aid_settings: AidSettings align(1) = .{},
    drs: Drs align(1) = .{},
    pit_limiter: i32 align(1) = 0,
    push_to_pass: PushToPass align(1) = .{},
    brake_bias: f32 align(1) = 0,
    drs_num_activations_total: i32 align(1) = 0,
    ptp_num_activations_total: i32 align(1) = 0,
    battery_soc: f32 align(1) = 0,
    water_left: f32 align(1) = 0,
    abs_setting: i32 align(1) = 0,
    headlights: i32 align(1) = 0,
    steer_wheel_max_rotation: i32 align(1) = 0,

    tire_type: i32 align(1) = 0,
    tire_rps: [tire_index_max]f32 align(1) = @splat(0),
    tire_speed: [tire_index_max]f32 align(1) = @splat(0),
    tire_grip: [tire_index_max]f32 align(1) = @splat(0),
    tire_wear: [tire_index_max]f32 align(1) = @splat(0),
    tire_flatspot: [tire_index_max]i32 align(1) = @splat(0),
    tire_pressure: [tire_index_max]f32 align(1) = @splat(0),
    tire_dirt: [tire_index_max]f32 align(1) = @splat(0),
    tire_temp: [tire_index_max]TireTemp align(1) = @splat(.{}),
    tire_type_front: i32 align(1) = 0,
    tire_type_rear: i32 align(1) = 0,
    tire_subtype_front: i32 align(1) = 0,
    tire_subtype_rear: i32 align(1) = 0,
    brake_temp: [tire_index_max]BrakeTemp align(1) = @splat(.{}),
    brake_pressure: [tire_index_max]f32 align(1) = @splat(0),

    traction_control_setting: i32 align(1) = 0,
    engine_map_setting: i32 align(1) = 0,
    engine_brake_setting: i32 align(1) = 0,
    traction_control_percent: f32 align(1) = 0,
    tire_on_mtrl: [tire_index_max]i32 align(1) = @splat(0),
    tire_load: [tire_index_max]f32 align(1) = @splat(0),

    car_damage: CarDamage align(1) = .{},

    num_cars: i32 align(1) = 0,
    all_drivers: [num_drivers_max]DriverData align(1) = @splat(.{}),

    pub fn gameModeValue(self: *const Shared) GameMode {
        return @enumFromInt(self.game_mode);
    }

    pub fn sessionTypeValue(self: *const Shared) SessionType {
        return @enumFromInt(self.session_type);
    }

    pub fn sessionPhaseValue(self: *const Shared) SessionPhase {
        return @enumFromInt(self.session_phase);
    }

    pub fn controlTypeValue(self: *const Shared) Control {
        return @enumFromInt(self.control_type);
    }

    pub fn finishStatusValue(self: *const Shared) FinishStatus {
        return @enumFromInt(self.finish_status);
    }

    pub fn pitWindowValue(self: *const Shared) PitWindow {
        return @enumFromInt(self.pit_window_status);
    }

    pub fn sessionLengthFormatValue(self: *const Shared) SessionLengthFormat {
        return @enumFromInt(self.session_length_format);
    }

    pub fn trackName(self: *const Shared) []const u8 {
        return strings.cString(&self.track_name);
    }

    pub fn layoutName(self: *const Shared) []const u8 {
        return strings.cString(&self.layout_name);
    }

    pub fn playerName(self: *const Shared) []const u8 {
        return strings.cString(&self.player_name);
    }

    pub fn speedKmh(self: *const Shared) f32 {
        return self.car_speed * mps_to_kmh;
    }

    pub fn engineRpm(self: *const Shared) f32 {
        return self.engine_rps * rps_to_rpm;
    }

    pub fn maxEngineRpm(self: *const Shared) f32 {
        return self.max_engine_rps * rps_to_rpm;
    }

    pub fn displayGear(self: *const Shared) i32 {
        return self.gear;
    }
};

pub fn readVersionMajor(view: []const u8) ?i32 {
    if (view.len < 4) return null;
    return std.mem.readInt(i32, view[0..4], .little);
}

pub fn readVersionMinor(view: []const u8) ?i32 {
    if (view.len < 8) return null;
    return std.mem.readInt(i32, view[4..8], .little);
}

pub fn readSimulationTicks(view: []const u8) ?i32 {
    const offset = @offsetOf(Shared, "player") + @offsetOf(PlayerData, "game_simulation_ticks");
    if (view.len < offset + 4) return null;
    return std.mem.readInt(i32, view[offset..][0..4], .little);
}

pub fn readNumCars(view: []const u8) ?i32 {
    const offset = @offsetOf(Shared, "num_cars");
    if (view.len < offset + 4) return null;
    return std.mem.readInt(i32, view[offset..][0..4], .little);
}

test "packed layout matches official r3e.h v3.5" {
    try std.testing.expectEqual(shared_size, @sizeOf(Shared));
    try std.testing.expectEqual(player_data_size, @sizeOf(PlayerData));
    try std.testing.expectEqual(driver_data_size, @sizeOf(DriverData));
    try std.testing.expectEqual(driver_info_size, @sizeOf(DriverInfo));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(Flags));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(CarDamage));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(CutTrackPenalties));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Drs));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(PushToPass));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TireTemp));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(BrakeTemp));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(AidSettings));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Shared, "version_major"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Shared, "player"));
    try std.testing.expectEqual(@as(usize, 44), @offsetOf(Shared, "player") + @offsetOf(PlayerData, "game_simulation_ticks"));
    try std.testing.expectEqual(@as(usize, 600), @offsetOf(Shared, "track_name"));
    try std.testing.expectEqual(@as(usize, 1196), @offsetOf(Shared, "vehicle_info"));
    try std.testing.expectEqual(@as(usize, 1324), @offsetOf(Shared, "player_name"));
    try std.testing.expectEqual(@as(usize, 1392), @offsetOf(Shared, "car_speed"));
    try std.testing.expectEqual(@as(usize, 1396), @offsetOf(Shared, "engine_rps"));
    try std.testing.expectEqual(@as(usize, 1408), @offsetOf(Shared, "gear"));
    try std.testing.expectEqual(@as(usize, 2008), @offsetOf(Shared, "num_cars"));
    try std.testing.expectEqual(shared_core_size, @offsetOf(Shared, "all_drivers"));
    try std.testing.expectEqual(shared_core_size + num_drivers_max * driver_data_size, @sizeOf(Shared));
}

test "string and unit helpers" {
    var s: Shared = .{};
    @memcpy(s.track_name[0.."Monza".len], "Monza");
    @memcpy(s.layout_name[0.."GP".len], "GP");
    @memcpy(s.player_name[0.."Driver".len], "Driver");
    @memcpy(s.vehicle_info.name[0.."BMW M4 GT3".len], "BMW M4 GT3");
    s.car_speed = 50.0;
    s.engine_rps = 100.0 * (2.0 * std.math.pi) / 60.0;
    s.gear = 3;
    s.session_type = @intFromEnum(SessionType.race);
    s.session_phase = @intFromEnum(SessionPhase.green);

    try std.testing.expectEqualStrings("Monza", s.trackName());
    try std.testing.expectEqualStrings("GP", s.layoutName());
    try std.testing.expectEqualStrings("Driver", s.playerName());
    try std.testing.expectEqualStrings("BMW M4 GT3", s.vehicle_info.nameUtf8());
    try std.testing.expectApproxEqAbs(@as(f32, 180.0), s.speedKmh(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), s.engineRpm(), 0.05);
    try std.testing.expectEqual(@as(i32, 3), s.displayGear());
    try std.testing.expectEqual(SessionType.race, s.sessionTypeValue());
    try std.testing.expectEqualStrings("Race", s.sessionTypeValue().label());
    try std.testing.expectEqualStrings("Green", s.sessionPhaseValue().label());
}

test "version and tick readers" {
    var bytes: [shared_core_size]u8 = undefined;
    @memset(&bytes, 0);
    std.mem.writeInt(i32, bytes[0..4], 3, .little);
    std.mem.writeInt(i32, bytes[4..8], 5, .little);
    const ticks_off = @offsetOf(Shared, "player") + @offsetOf(PlayerData, "game_simulation_ticks");
    std.mem.writeInt(i32, bytes[ticks_off..][0..4], 12345, .little);
    std.mem.writeInt(i32, bytes[@offsetOf(Shared, "num_cars")..][0..4], 12, .little);

    try std.testing.expectEqual(@as(i32, 3), readVersionMajor(&bytes).?);
    try std.testing.expectEqual(@as(i32, 5), readVersionMinor(&bytes).?);
    try std.testing.expectEqual(@as(i32, 12345), readSimulationTicks(&bytes).?);
    try std.testing.expectEqual(@as(i32, 12), readNumCars(&bytes).?);
}
