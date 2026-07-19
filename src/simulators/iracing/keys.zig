//! Commonly used IRSDK session map keys and telemetry variable names.
//!
//! These are optional conveniences — all session fields and telemetry variables
//! remain discoverable from parsed snapshots.

/// Keys in the parsed session-info tree.
pub const session = struct {
    pub const weekend_info = "WeekendInfo";
    pub const driver_info = "DriverInfo";
    pub const session_info = "SessionInfo";
    pub const drivers = "Drivers";

    pub const track_name = "TrackName";
    pub const track_display_name = "TrackDisplayName";
    pub const track_config_name = "TrackConfigName";
    pub const track_length = "TrackLength";
    pub const track_length_official = "TrackLengthOfficial";
    pub const session_type = "SessionType";
    pub const race_week = "RaceWeek";

    pub const driver_car_idx = "DriverCarIdx";
    pub const driver_user_name = "DriverUserName";
    pub const session_laps = "SessionLaps";
    pub const session_time = "SessionTime";
};

/// Leaf keys inside a `DriverInfo/Drivers` list item.
///
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
