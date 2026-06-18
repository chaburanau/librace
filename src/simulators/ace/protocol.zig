//! Assetto Corsa Evo shared-memory layout.
//!
//! Reference: official "Shared Memory Documentation" (AC Evo, v1) and the community
//! C++ header used by typed bindings (dSyncro/acevo-shared-memory). AC Evo inherits the
//! classic Assetto Corsa three-page model — physics, graphics, static — but renames the
//! map tags and extends every page with new fields and embedded sub-structs.
//!
//! Layout notes:
//! - The C++ structs are declared under `#pragma pack(4)`, so every field aligns to
//!   `min(natural_alignment, 4)`. The only types whose natural alignment exceeds 4 are the
//!   64-bit car id fields, which are therefore marked `align(4)` here. Every other field
//!   (i8/u8/bool = 1, short = 2, int/float = 4, char arrays = 1) already matches a Zig
//!   `extern struct`, so no further packing directives are required.
//! - All scalars are little-endian (Windows/x86-64).
//! - Pages are single, in-place structs (not ring-buffered). `packetId` increments on each
//!   update and is used to detect new data and torn reads.

const std = @import("std");

/// Windows named shared-memory tags. The `Local\\` prefix selects the per-session namespace.
pub const physics_map_name = "Local\\acevo_pmf_physics";
pub const graphics_map_name = "Local\\acevo_pmf_graphics";
pub const static_map_name = "Local\\acevo_pmf_static";

/// Current operational state of the simulator (`SPageFileGraphicEvo.status`).
pub const Status = enum(i32) {
    off = 0,
    replay = 1,
    live = 2,
    pause = 3,
    _,
};

/// Type of racing session currently loaded (`SPageFileStaticEvo.session`).
pub const SessionType = enum(i32) {
    unknown = -1,
    time_attack = 0,
    race = 1,
    hot_stint = 2,
    cruise = 3,
    _,

    pub fn label(self: SessionType) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .time_attack => "Time Attack",
            .race => "Race",
            .hot_stint => "Hot Stint",
            .cruise => "Cruise",
            _ => "?",
        };
    }
};

/// Race flag currently shown to the driver.
pub const FlagType = enum(i32) {
    none = 0,
    white = 1,
    green = 2,
    red = 3,
    blue = 4,
    yellow = 5,
    black = 6,
    black_white = 7,
    checkered = 8,
    orange_circle = 9,
    red_yellow_stripes = 10,
    _,
};

/// Where on the circuit the car is currently positioned.
pub const CarLocation = enum(i32) {
    unassigned = 0,
    pit_lane = 1,
    pit_entry = 2,
    pit_exit = 3,
    track = 4,
    _,

    pub fn label(self: CarLocation) []const u8 {
        return switch (self) {
            .unassigned => "—",
            .pit_lane => "Pit Lane",
            .pit_entry => "Pit Entry",
            .pit_exit => "Pit Exit",
            .track => "Track",
            _ => "?",
        };
    }
};

/// Powertrain type of the player car.
pub const EngineType = enum(i32) {
    internal_combustion = 0,
    electric_motor = 1,
    _,
};

/// Initial grip conditions at session start.
pub const StartingGrip = enum(i32) {
    green = 0,
    fast = 1,
    optimum = 2,
    _,
};

/// Raw physics telemetry, updated every simulation step (`Local\\acevo_pmf_physics`).
pub const Physics = extern struct {
    packet_id: i32 = 0,
    gas: f32 = 0,
    brake: f32 = 0,
    fuel: f32 = 0,
    gear: i32 = 0,
    rpms: i32 = 0,
    steer_angle: f32 = 0,
    speed_kmh: f32 = 0,
    velocity: [3]f32 = .{ 0, 0, 0 },
    acc_g: [3]f32 = .{ 0, 0, 0 },
    wheel_slip: [4]f32 = .{ 0, 0, 0, 0 },
    wheel_load: [4]f32 = .{ 0, 0, 0, 0 },
    wheels_pressure: [4]f32 = .{ 0, 0, 0, 0 },
    wheel_angular_speed: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_wear: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_dirty_level: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_core_temperature: [4]f32 = .{ 0, 0, 0, 0 },
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
    auto_shifter_on: i32 = 0,
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
    p2p_activations: i32 = 0,
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
    brake_torque: [4]f32 = .{ 0, 0, 0, 0 },
    front_brake_compound: i32 = 0,
    rear_brake_compound: i32 = 0,
    pad_life: [4]f32 = .{ 0, 0, 0, 0 },
    disc_life: [4]f32 = .{ 0, 0, 0, 0 },
    ignition_on: i32 = 0,
    starter_engine_on: i32 = 0,
    is_engine_running: i32 = 0,
    kerb_vibration: f32 = 0,
    slip_vibrations: f32 = 0,
    road_vibrations: f32 = 0,
    abs_vibrations: f32 = 0,
};

/// Complete state of a single tyre corner (256 bytes). Embedded four times in the graphics page.
pub const TyreState = extern struct {
    slip: f32 = 0,
    lock: bool = false,
    tyre_pression: f32 = 0,
    tyre_temperature_c: f32 = 0,
    brake_temperature_c: f32 = 0,
    brake_pressure: f32 = 0,
    tyre_temperature_left: f32 = 0,
    tyre_temperature_center: f32 = 0,
    tyre_temperature_right: f32 = 0,
    tyre_compound_front: [33]u8 = @splat(0),
    tyre_compound_rear: [33]u8 = @splat(0),
    tyre_normalized_pressure: f32 = 0,
    tyre_normalized_temperature_left: f32 = 0,
    tyre_normalized_temperature_center: f32 = 0,
    tyre_normalized_temperature_right: f32 = 0,
    brake_normalized_temperature: f32 = 0,
    tyre_normalized_temperature_core: f32 = 0,
    place_holder: [128]u8 = @splat(0),
};

/// Structural damage level per body zone (128 bytes).
pub const DamageState = extern struct {
    damage_front: f32 = 0,
    damage_rear: f32 = 0,
    damage_left: f32 = 0,
    damage_right: f32 = 0,
    damage_center: f32 = 0,
    damage_suspension_lf: f32 = 0,
    damage_suspension_rf: f32 = 0,
    damage_suspension_lr: f32 = 0,
    damage_suspension_rr: f32 = 0,
    place_holder: [92]u8 = @splat(0),
};

/// Status of each pit-stop service action (64 bytes). −1 skip, 0 done, 1 in progress.
pub const PitInfo = extern struct {
    damage: i8 = 0,
    fuel: i8 = 0,
    tyres_lf: i8 = 0,
    tyres_rf: i8 = 0,
    tyres_lr: i8 = 0,
    tyres_rr: i8 = 0,
    place_holder: [58]u8 = @splat(0),
};

/// Driver-adjustable electronic aid and setup settings (128 bytes).
pub const Electronics = extern struct {
    tc_level: i8 = 0,
    tc_cut_level: i8 = 0,
    abs_level: i8 = 0,
    esc_level: i8 = 0,
    ebb_level: i8 = 0,
    brake_bias: f32 = 0,
    engine_map_level: i8 = 0,
    turbo_level: f32 = 0,
    ers_deployment_map: i8 = 0,
    ers_recharge_map: f32 = 0,
    is_ers_heat_charging_on: bool = false,
    is_ers_overtake_mode_on: bool = false,
    is_drs_open: bool = false,
    diff_power_level: i8 = 0,
    diff_coast_level: i8 = 0,
    front_bump_damper_level: i8 = 0,
    front_rebound_damper_level: i8 = 0,
    rear_bump_damper_level: i8 = 0,
    rear_rebound_damper_level: i8 = 0,
    is_ignition_on: bool = false,
    is_pitlimiter_on: bool = false,
    active_performance_mode: i8 = 0,
    place_holder: [88]u8 = @splat(0),
};

/// Cockpit light, display, and instrumentation panel states (128 bytes).
pub const Instrumentation = extern struct {
    main_light_stage: i8 = 0,
    special_light_stage: i8 = 0,
    cockpit_light_stage: i8 = 0,
    wiper_level: i8 = 0,
    rain_lights: bool = false,
    direction_light_left: bool = false,
    direction_light_right: bool = false,
    flashing_lights: bool = false,
    warning_lights: bool = false,
    selected_display_index: i8 = 0,
    display_current_page_index: [16]i8 = @splat(0),
    are_headlights_visible: bool = false,
    place_holder: [101]u8 = @splat(0),
};

/// Server-side session lifecycle information (256 bytes).
pub const SessionState = extern struct {
    phase_name: [33]u8 = @splat(0),
    time_left: [15]u8 = @splat(0),
    time_left_ms: i32 = 0,
    wait_time: [15]u8 = @splat(0),
    total_lap: i32 = 0,
    current_lap: i32 = 0,
    lights_on: i32 = 0,
    lights_mode: i32 = 0,
    lap_length_km: f32 = 0,
    end_session_flag: i32 = 0,
    time_to_next_session: [15]u8 = @splat(0),
    disconnected_from_server: bool = false,
    restart_season_enabled: bool = false,
    ui_enable_drive: bool = false,
    ui_enable_setup: bool = false,
    is_ready_to_next_blinking: bool = false,
    show_waiting_for_players: bool = false,
    place_holder: [140]u8 = @splat(0),
};

/// Lap timing and delta values displayed on the HUD (256 bytes).
pub const TimingState = extern struct {
    current_laptime: [15]u8 = @splat(0),
    delta_current: [15]u8 = @splat(0),
    delta_current_p: i32 = 0,
    last_laptime: [15]u8 = @splat(0),
    delta_last: [15]u8 = @splat(0),
    delta_last_p: i32 = 0,
    best_laptime: [15]u8 = @splat(0),
    ideal_laptime: [15]u8 = @splat(0),
    total_time: [15]u8 = @splat(0),
    is_invalid: bool = false,
    place_holder: [137]u8 = @splat(0),
};

/// Driver-assist settings currently active for the player car (64 bytes).
pub const AssistsState = extern struct {
    auto_gear: u8 = 0,
    auto_blip: u8 = 0,
    auto_clutch: u8 = 0,
    auto_clutch_on_start: u8 = 0,
    manual_ignition_e_start: u8 = 0,
    auto_pit_limiter: u8 = 0,
    standing_start_assist: u8 = 0,
    auto_steer: f32 = 0,
    arcade_stability_control: f32 = 0,
    place_holder: [48]u8 = @splat(0),
};

/// Main HUD and graphics telemetry page (`Local\\acevo_pmf_graphics`), updated per frame.
pub const Graphics = extern struct {
    packet_id: i32 = 0,
    status: i32 = 0,
    focused_car_id_a: u64 align(4) = 0,
    focused_car_id_b: u64 align(4) = 0,
    player_car_id_a: u64 align(4) = 0,
    player_car_id_b: u64 align(4) = 0,
    rpm: u16 = 0,
    is_rpm_limiter_on: bool = false,
    is_change_up_rpm: bool = false,
    is_change_down_rpm: bool = false,
    tc_active: bool = false,
    abs_active: bool = false,
    esc_active: bool = false,
    launch_active: bool = false,
    is_ignition_on: bool = false,
    is_engine_running: bool = false,
    kers_is_charging: bool = false,
    is_wrong_way: bool = false,
    is_drs_available: bool = false,
    battery_is_charging: bool = false,
    is_max_kj_per_lap_reached: bool = false,
    is_max_charge_kj_per_lap_reached: bool = false,
    display_speed_kmh: i16 = 0,
    display_speed_mph: i16 = 0,
    display_speed_ms: i16 = 0,
    pitspeeding_delta: f32 = 0,
    gear_int: i16 = 0,
    rpm_percent: f32 = 0,
    gas_percent: f32 = 0,
    brake_percent: f32 = 0,
    handbrake_percent: f32 = 0,
    clutch_percent: f32 = 0,
    steering_percent: f32 = 0,
    ffb_strength: f32 = 0,
    car_ffb_mupliplier: f32 = 0,
    water_temperature_percent: f32 = 0,
    water_pressure_bar: f32 = 0,
    fuel_pressure_bar: f32 = 0,
    water_temperature_c: i8 = 0,
    air_temperature_c: i8 = 0,
    oil_temperature_c: f32 = 0,
    oil_pressure_bar: f32 = 0,
    exhaust_temperature_c: f32 = 0,
    g_forces_x: f32 = 0,
    g_forces_y: f32 = 0,
    g_forces_z: f32 = 0,
    turbo_boost: f32 = 0,
    turbo_boost_level: f32 = 0,
    turbo_boost_perc: f32 = 0,
    steer_degrees: i32 = 0,
    current_km: f32 = 0,
    total_km: u32 = 0,
    total_driving_time_s: u32 = 0,
    time_of_day_hours: i32 = 0,
    time_of_day_minutes: i32 = 0,
    time_of_day_seconds: i32 = 0,
    delta_time_ms: i32 = 0,
    current_lap_time_ms: i32 = 0,
    predicted_lap_time_ms: i32 = 0,
    fuel_liter_current_quantity: f32 = 0,
    fuel_liter_current_quantity_percent: f32 = 0,
    fuel_liter_per_km: f32 = 0,
    km_per_fuel_liter: f32 = 0,
    current_torque: f32 = 0,
    current_bhp: i32 = 0,
    tyre_lf: TyreState = .{},
    tyre_rf: TyreState = .{},
    tyre_lr: TyreState = .{},
    tyre_rr: TyreState = .{},
    npos: f32 = 0,
    kers_charge_perc: f32 = 0,
    kers_current_perc: f32 = 0,
    control_lock_time: f32 = 0,
    car_damage: DamageState = .{},
    car_location: i32 = 0,
    pit_info: PitInfo = .{},
    fuel_liter_used: f32 = 0,
    fuel_liter_per_lap: f32 = 0,
    laps_possible_with_fuel: f32 = 0,
    battery_temperature: f32 = 0,
    battery_voltage: f32 = 0,
    instantaneous_fuel_liter_per_km: f32 = 0,
    instantaneous_km_per_fuel_liter: f32 = 0,
    gear_rpm_window: f32 = 0,
    instrumentation: Instrumentation = .{},
    instrumentation_min_limit: Instrumentation = .{},
    instrumentation_max_limit: Instrumentation = .{},
    electronics: Electronics = .{},
    electronics_min_limit: Electronics = .{},
    electronics_max_limit: Electronics = .{},
    electronics_is_modifiable: Electronics = .{},
    total_lap_count: i32 = 0,
    current_pos: u32 = 0,
    total_drivers: u32 = 0,
    last_laptime_ms: i32 = 0,
    best_laptime_ms: i32 = 0,
    flag: i32 = 0,
    global_flag: i32 = 0,
    max_gears: u32 = 0,
    engine_type: i32 = 0,
    has_kers: bool = false,
    is_last_lap: bool = false,
    performance_mode_name: [33]u8 = @splat(0),
    diff_coast_raw_value: f32 = 0,
    diff_power_raw_value: f32 = 0,
    race_cut_gained_time_ms: i32 = 0,
    distance_to_deadline: i32 = 0,
    race_cut_current_delta: f32 = 0,
    session_state: SessionState = .{},
    timing_state: TimingState = .{},
    player_ping: i32 = 0,
    player_latency: i32 = 0,
    player_cpu_usage: i32 = 0,
    player_cpu_usage_avg: i32 = 0,
    player_qos: i32 = 0,
    player_qos_avg: i32 = 0,
    player_fps: i32 = 0,
    player_fps_avg: i32 = 0,
    driver_name: [33]u8 = @splat(0),
    driver_surname: [33]u8 = @splat(0),
    car_model: [33]u8 = @splat(0),
    is_in_pit_box: bool = false,
    is_in_pit_lane: bool = false,
    is_valid_lap: bool = false,
    car_coordinates: [60][3]f32 = @splat(@splat(0)),
    gap_ahead: f32 = 0,
    gap_behind: f32 = 0,
    active_cars: u8 = 0,
    fuel_per_lap: f32 = 0,
    fuel_estimated_laps: f32 = 0,
    assists_state: AssistsState = .{},
    max_fuel: f32 = 0,
    max_turbo_boost: f32 = 0,
    use_single_compound: bool = false,
    car_ids: [60][2]u64 align(4) = @splat(@splat(0)),

    pub fn statusValue(self: *const Graphics) Status {
        return @enumFromInt(self.status);
    }

    pub fn flagValue(self: *const Graphics) FlagType {
        return @enumFromInt(self.flag);
    }

    pub fn carLocationValue(self: *const Graphics) CarLocation {
        return @enumFromInt(self.car_location);
    }

    pub fn engineTypeValue(self: *const Graphics) EngineType {
        return @enumFromInt(self.engine_type);
    }
};

/// Static session metadata (`Local\\acevo_pmf_static`), written once when a session loads.
pub const Static = extern struct {
    sm_version: [15]u8 = @splat(0),
    ac_evo_version: [15]u8 = @splat(0),
    session: i32 = -1,
    session_name: [33]u8 = @splat(0),
    event_id: u8 = 0,
    session_id: u8 = 0,
    starting_grip: i32 = 0,
    starting_ambient_temperature_c: f32 = 0,
    starting_ground_temperature_c: f32 = 0,
    is_static_weather: bool = false,
    is_timed_race: bool = false,
    is_online: bool = false,
    number_of_sessions: i32 = 0,
    nation: [33]u8 = @splat(0),
    longitude: f32 = 0,
    latitude: f32 = 0,
    track: [33]u8 = @splat(0),
    track_configuration: [33]u8 = @splat(0),
    track_length_m: f32 = 0,

    pub fn sessionValue(self: *const Static) SessionType {
        return @enumFromInt(self.session);
    }

    pub fn startingGripValue(self: *const Static) StartingGrip {
        return @enumFromInt(self.starting_grip);
    }
};

/// Trim a fixed-size C char buffer to its NUL-terminated string slice.
pub fn cString(buf: []const u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

/// `packetId` lives at offset 0 of both live pages; read it without a full struct copy.
pub fn readPacketId(view: []const u8) ?i32 {
    if (view.len < 4) return null;
    return std.mem.readInt(i32, view[0..4], .little);
}

test "sub-struct sizes match the documented fixed layout" {
    try std.testing.expectEqual(@as(usize, 256), @sizeOf(TyreState));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(DamageState));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(PitInfo));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(Electronics));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(Instrumentation));
    try std.testing.expectEqual(@as(usize, 256), @sizeOf(SessionState));
    try std.testing.expectEqual(@as(usize, 256), @sizeOf(TimingState));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(AssistsState));
}

test "pack(4) keeps 64-bit ids 4-aligned (no struct-wide 8-byte alignment)" {
    try std.testing.expectEqual(@as(usize, 4), @alignOf(Graphics));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Graphics, "focused_car_id_a"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Graphics, "rpm"));
}

test "physics scalar offsets are tightly packed from the page start" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Physics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Physics, "gas"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Physics, "gear"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(Physics, "rpms"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Physics, "speed_kmh"));
}

test "static page string and scalar offsets" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Static, "sm_version"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Static, "session"));
    try std.testing.expectEqual(@as(usize, 208), @sizeOf(Static));
}

test "cString trims at the NUL terminator" {
    const buf = [_]u8{ 'S', 'p', 'a', 0, 'x', 0 };
    try std.testing.expectEqualStrings("Spa", cString(&buf));
}
