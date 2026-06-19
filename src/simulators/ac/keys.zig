//! Commonly used Assetto Corsa field names, grouped by shared-memory page.
//!
//! These are optional conveniences for `getNumber`/`getString`/`getRaw`/`resolve`; every field
//! remains reachable through typed struct access (`client.physics()`, `client.graphics()`,
//! `client.static()`).

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
    pub const local_velocity = "local_velocity";
    pub const acc_g = "acc_g";
    pub const wheel_slip = "wheel_slip";
    pub const wheel_load = "wheel_load";
    pub const wheels_pressure = "wheels_pressure";
    pub const tyre_core_temperature = "tyre_core_temperature";
    pub const tyre_temp_i = "tyre_temp_i";
    pub const tyre_temp_m = "tyre_temp_m";
    pub const tyre_temp_o = "tyre_temp_o";
    pub const suspension_travel = "suspension_travel";
    pub const tc = "tc";
    pub const abs = "abs";
    pub const heading = "heading";
    pub const pitch = "pitch";
    pub const roll = "roll";
    pub const turbo_boost = "turbo_boost";
    pub const air_temp = "air_temp";
    pub const road_temp = "road_temp";
    pub const brake_bias = "brake_bias";
    pub const pit_limiter_on = "pit_limiter_on";
};

/// Field names on the graphics page (`Client.graphics`, per-frame HUD/session state).
pub const graphics = struct {
    pub const packet_id = "packet_id";
    pub const status = "status";
    pub const session = "session";
    pub const completed_laps = "completed_laps";
    pub const position = "position";
    pub const i_current_time = "i_current_time";
    pub const i_last_time = "i_last_time";
    pub const i_best_time = "i_best_time";
    pub const session_time_left = "session_time_left";
    pub const distance_traveled = "distance_traveled";
    pub const is_in_pit = "is_in_pit";
    pub const is_in_pit_lane = "is_in_pit_lane";
    pub const current_sector_index = "current_sector_index";
    pub const number_of_laps = "number_of_laps";
    pub const normalized_car_position = "normalized_car_position";
    pub const flag = "flag";
    pub const surface_grip = "surface_grip";
    pub const mandatory_pit_done = "mandatory_pit_done";
    pub const wind_speed = "wind_speed";
    pub const wind_direction = "wind_direction";

    // wchar string fields.
    pub const current_time = "current_time";
    pub const last_time = "last_time";
    pub const best_time = "best_time";
    pub const split = "split";
    pub const tyre_compound = "tyre_compound";
};

/// Field names on the static page (`Client.static`, session metadata written once on load).
pub const static = struct {
    pub const number_of_sessions = "number_of_sessions";
    pub const num_cars = "num_cars";
    pub const sector_count = "sector_count";
    pub const max_torque = "max_torque";
    pub const max_power = "max_power";
    pub const max_rpm = "max_rpm";
    pub const max_fuel = "max_fuel";
    pub const max_turbo_boost = "max_turbo_boost";
    pub const air_temp = "air_temp";
    pub const road_temp = "road_temp";
    pub const track_spline_length = "track_spline_length";
    pub const pit_window_start = "pit_window_start";
    pub const pit_window_end = "pit_window_end";

    // wchar string fields.
    pub const sm_version = "sm_version";
    pub const ac_version = "ac_version";
    pub const car_model = "car_model";
    pub const track = "track";
    pub const player_name = "player_name";
    pub const player_surname = "player_surname";
    pub const player_nick = "player_nick";
    pub const track_configuration = "track_configuration";
    pub const car_skin = "car_skin";
};
