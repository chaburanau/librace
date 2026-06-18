//! Commonly used AC Evo field names, grouped by shared-memory page.
//!
//! These are optional conveniences for the generic `getNumber`/`getRaw`/`resolve` APIs —
//! every field also remains reachable via typed struct access (`client.physics()`,
//! `client.graphics()`, `client.static()`). Names match the protocol field identifiers.

/// Field names on the physics page (`Client.physics`, high-rate vehicle dynamics).
pub const physics = struct {
    pub const packet_id = "packet_id";
    pub const gas = "gas";
    pub const brake = "brake";
    pub const clutch = "clutch";
    pub const fuel = "fuel";
    pub const gear = "gear";
    pub const rpms = "rpms";
    pub const steer_angle = "steer_angle";
    pub const speed_kmh = "speed_kmh";
    pub const velocity = "velocity";
    pub const acc_g = "acc_g";
    pub const wheel_slip = "wheel_slip";
    pub const wheel_load = "wheel_load";
    pub const wheels_pressure = "wheels_pressure";
    pub const tyre_core_temperature = "tyre_core_temperature";
    pub const suspension_travel = "suspension_travel";
    pub const drs = "drs";
    pub const tc = "tc";
    pub const abs = "abs";
    pub const heading = "heading";
    pub const pitch = "pitch";
    pub const roll = "roll";
    pub const turbo_boost = "turbo_boost";
    pub const air_temp = "air_temp";
    pub const road_temp = "road_temp";
    pub const water_temp = "water_temp";
    pub const brake_bias = "brake_bias";
    pub const pit_limiter_on = "pit_limiter_on";
    pub const is_engine_running = "is_engine_running";
    pub const current_max_rpm = "current_max_rpm";
};

/// Field names on the graphics page (`Client.graphics`, per-frame HUD/session state).
pub const graphics = struct {
    pub const packet_id = "packet_id";
    pub const status = "status";
    pub const rpm = "rpm";
    pub const gear_int = "gear_int";
    pub const rpm_percent = "rpm_percent";
    pub const gas_percent = "gas_percent";
    pub const brake_percent = "brake_percent";
    pub const clutch_percent = "clutch_percent";
    pub const steering_percent = "steering_percent";
    pub const steer_degrees = "steer_degrees";
    pub const g_forces_x = "g_forces_x";
    pub const g_forces_y = "g_forces_y";
    pub const g_forces_z = "g_forces_z";
    pub const npos = "npos";
    pub const current_lap_time_ms = "current_lap_time_ms";
    pub const last_laptime_ms = "last_laptime_ms";
    pub const best_laptime_ms = "best_laptime_ms";
    pub const delta_time_ms = "delta_time_ms";
    pub const total_lap_count = "total_lap_count";
    pub const current_pos = "current_pos";
    pub const total_drivers = "total_drivers";
    pub const fuel_liter_current_quantity = "fuel_liter_current_quantity";
    pub const fuel_liter_per_lap = "fuel_liter_per_lap";
    pub const laps_possible_with_fuel = "laps_possible_with_fuel";
    pub const car_location = "car_location";
    pub const flag = "flag";
    pub const max_gears = "max_gears";
    pub const max_fuel = "max_fuel";
    pub const is_in_pit_lane = "is_in_pit_lane";
    pub const is_valid_lap = "is_valid_lap";

    // String fields.
    pub const driver_name = "driver_name";
    pub const driver_surname = "driver_surname";
    pub const car_model = "car_model";
    pub const performance_mode_name = "performance_mode_name";
};

/// Field names on the static page (`Client.static`, session metadata written once on load).
pub const static = struct {
    pub const session = "session";
    pub const starting_grip = "starting_grip";
    pub const starting_ambient_temperature_c = "starting_ambient_temperature_c";
    pub const starting_ground_temperature_c = "starting_ground_temperature_c";
    pub const number_of_sessions = "number_of_sessions";
    pub const longitude = "longitude";
    pub const latitude = "latitude";
    pub const track_length_m = "track_length_m";

    // String fields.
    pub const sm_version = "sm_version";
    pub const ac_evo_version = "ac_evo_version";
    pub const session_name = "session_name";
    pub const nation = "nation";
    pub const track = "track";
    pub const track_configuration = "track_configuration";
};
