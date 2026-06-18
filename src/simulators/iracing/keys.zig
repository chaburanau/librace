//! Commonly used IRSDK session paths and telemetry variable names.
//!
//! These are optional conveniences — all session fields and telemetry variables
//! remain accessible by path or name via the client API.
//!
//! Session paths use `Section/Key` or `Section/Nested/.../Key`. Keys inside YAML
//! lists (e.g. `DriverInfo/CarScreenName`) match the first occurrence in the section.

/// Session-info YAML paths (`Section/Key`, slash-separated).
pub const session = struct {
    pub const track_name = "WeekendInfo/TrackName";
    pub const track_display_name = "WeekendInfo/TrackDisplayName";
    pub const track_config_name = "WeekendInfo/TrackConfigName";
    pub const track_length = "WeekendInfo/TrackLength";
    pub const track_length_official = "WeekendInfo/TrackLengthOfficial";
    pub const session_type = "WeekendInfo/SessionType";
    pub const race_week = "WeekendInfo/RaceWeek";

    pub const driver_car_idx = "DriverInfo/DriverCarIdx";
    pub const driver_user_name = "DriverInfo/DriverUserName";
    /// First `CarScreenName` found in the DriverInfo section.
    ///
    /// In multi-car sessions this is the *first* driver, not necessarily the player.
    /// Prefer `Client.playerDriverGet(keys.driver.car_screen_name)` for the player's car.
    pub const car_screen_name = "DriverInfo/CarScreenName";
    pub const car_path = "DriverInfo/CarPath";
    pub const car_class_id = "DriverInfo/CarClassID";

    pub const session_laps = "SessionInfo/SessionLaps";
    pub const session_time = "SessionInfo/SessionTime";
};

/// Leaf keys inside a `DriverInfo/Drivers` list item.
///
/// Use with `Client.playerDriverGet`, which resolves the player's entry via `DriverCarIdx`.
pub const driver = struct {
    pub const car_idx = "CarIdx";
    pub const user_name = "UserName";
    pub const car_screen_name = "CarScreenName";
    pub const car_screen_name_short = "CarScreenNameShort";
    pub const car_path = "CarPath";
    pub const car_number = "CarNumber";
    pub const car_class_id = "CarClassID";
    pub const car_class_short_name = "CarClassShortName";
    pub const irating = "IRating";
    pub const team_name = "TeamName";
};

/// Live telemetry variable names (IRSDK `irsdk_varHeader.name`).
pub const var_name = struct {
    pub const speed = "Speed";
    pub const rpm = "RPM";
    pub const gear = "Gear";
    pub const throttle = "Throttle";
    pub const brake = "Brake";
    pub const clutch = "Clutch";
    pub const steering_wheel_angle = "SteeringWheelAngle";
    pub const lap = "Lap";
    pub const lap_current_lap_time = "LapCurrentLapTime";
    pub const lap_best_lap_time = "LapBestLapTime";
    pub const lap_last_lap_time = "LapLastLapTime";
    pub const session_state = "SessionState";
    pub const session_time = "SessionTime";
    pub const session_num = "SessionNum";
    pub const is_on_track = "IsOnTrack";
    pub const fuel_level = "FuelLevel";
    pub const fuel_use_per_hour = "FuelUsePerHour";
    pub const lat_accel = "LatAccel";
    pub const long_accel = "LongAccel";
    pub const vert_accel = "VertAccel";
    pub const yaw = "Yaw";
    pub const pitch = "Pitch";
    pub const roll = "Roll";
};
