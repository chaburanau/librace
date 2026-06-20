//! Commonly used Forza Horizon 6 Data Out field names.
//!
//! Optional conveniences for `getNumber`/`getRaw`/`resolve`; every field remains
//! reachable through typed access (`client.packet()`).

pub const packet = struct {
    pub const is_race_on = "is_race_on";
    pub const timestamp_ms = "timestamp_ms";
    pub const engine_max_rpm = "engine_max_rpm";
    pub const engine_idle_rpm = "engine_idle_rpm";
    pub const current_engine_rpm = "current_engine_rpm";
    pub const acceleration_x = "acceleration_x";
    pub const acceleration_y = "acceleration_y";
    pub const acceleration_z = "acceleration_z";
    pub const velocity_x = "velocity_x";
    pub const velocity_y = "velocity_y";
    pub const velocity_z = "velocity_z";
    pub const yaw = "yaw";
    pub const pitch = "pitch";
    pub const roll = "roll";
    pub const car_ordinal = "car_ordinal";
    pub const car_class = "car_class";
    pub const car_performance_index = "car_performance_index";
    pub const drivetrain_type = "drivetrain_type";
    pub const num_cylinders = "num_cylinders";
    pub const car_group = "car_group";
    pub const smashable_vel_diff = "smashable_vel_diff";
    pub const smashable_mass = "smashable_mass";
    pub const position_x = "position_x";
    pub const position_y = "position_y";
    pub const position_z = "position_z";
    pub const speed = "speed";
    pub const power = "power";
    pub const torque = "torque";
    pub const tire_temp_front_left = "tire_temp_front_left";
    pub const tire_temp_front_right = "tire_temp_front_right";
    pub const tire_temp_rear_left = "tire_temp_rear_left";
    pub const tire_temp_rear_right = "tire_temp_rear_right";
    pub const boost = "boost";
    pub const fuel = "fuel";
    pub const distance_traveled = "distance_traveled";
    pub const best_lap = "best_lap";
    pub const last_lap = "last_lap";
    pub const current_lap = "current_lap";
    pub const current_race_time = "current_race_time";
    pub const lap_number = "lap_number";
    pub const race_position = "race_position";
    pub const accel = "accel";
    pub const brake = "brake";
    pub const clutch = "clutch";
    pub const hand_brake = "hand_brake";
    pub const gear = "gear";
    pub const steer = "steer";
    pub const normalized_driving_line = "normalized_driving_line";
    pub const normalized_ai_brake_difference = "normalized_ai_brake_difference";
};
