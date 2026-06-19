//! Assetto Corsa shared-memory layout.
//!
//! Reference: Kunos' classic Assetto Corsa "Shared Memory Reference" (AC 1.5+), mirrored by
//! widely used community bindings such as mdjarv/assettocorsasharedmemory and CSP's
//! `acc-extension-apps` `sim_info.py`.
//!
//! Layout notes:
//! - AC exposes three Windows named mappings: `Local\\acpmf_physics`, `Local\\acpmf_graphics`,
//!   and `Local\\acpmf_static`.
//! - The C structs are declared `#pragma pack(4)`. The fields are 32-bit scalars and
//!   `wchar_t` strings, so Zig `extern struct` matches the documented layout including padding
//!   after odd-length UTF-16 string arrays.
//! - Strings are Windows `wchar_t` (UTF-16LE), represented here as `[N]u16`.
//! - Physics and graphics are in-place live pages with `packetId` at offset 0.

const std = @import("std");

/// Windows named shared-memory tags. The `Local\\` prefix selects the per-session namespace.
pub const physics_map_name = "Local\\acpmf_physics";
pub const graphics_map_name = "Local\\acpmf_graphics";
pub const static_map_name = "Local\\acpmf_static";

/// Current operational state of the simulator (`SPageFileGraphic.status`).
pub const Status = enum(i32) {
    off = 0,
    replay = 1,
    live = 2,
    pause = 3,
    _,
};

/// Type of session currently loaded (`SPageFileGraphic.session`).
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

/// Race flag currently shown to the driver (`SPageFileGraphic.flag`).
pub const FlagType = enum(i32) {
    none = 0,
    blue = 1,
    yellow = 2,
    black = 3,
    white = 4,
    checkered = 5,
    penalty = 6,
    _,
};

/// Raw physics telemetry, updated every simulation step (`Local\\acpmf_physics`).
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

    pub fn gearLabel(self: *const Physics, buf: []u8) []const u8 {
        return switch (self.gear) {
            0 => "R",
            1 => "N",
            else => std.fmt.bufPrint(buf, "{d}", .{self.gear - 1}) catch "?",
        };
    }
};

/// Per-frame HUD / session-progress telemetry (`Local\\acpmf_graphics`).
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
    car_coordinates: [3]f32 = .{ 0, 0, 0 },
    penalty_time: f32 = 0,
    flag: i32 = 0,
    ideal_line_on: i32 = 0,
    is_in_pit_lane: i32 = 0,
    surface_grip: f32 = 0,
    mandatory_pit_done: i32 = 0,
    wind_speed: f32 = 0,
    wind_direction: f32 = 0,

    pub fn statusValue(self: *const Graphics) Status {
        return @enumFromInt(self.status);
    }

    pub fn sessionValue(self: *const Graphics) SessionType {
        return @enumFromInt(self.session);
    }

    pub fn flagValue(self: *const Graphics) FlagType {
        return @enumFromInt(self.flag);
    }

    /// Synthesised location label (AC has pit booleans but no car-location enum).
    pub fn locationLabel(self: *const Graphics) []const u8 {
        if (self.is_in_pit != 0) return "Pit Box";
        if (self.is_in_pit_lane != 0) return "Pit Lane";
        return "Track";
    }
};

/// Static session/car metadata (`Local\\acpmf_static`), written once when a session loads.
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
    air_temp: f32 = 0,
    road_temp: f32 = 0,
    penalties_enabled: i32 = 0,
    aid_fuel_rate: f32 = 0,
    aid_tire_rate: f32 = 0,
    aid_mechanical_damage: f32 = 0,
    aid_allow_tyre_blankets: i32 = 0,
    aid_stability: f32 = 0,
    aid_auto_clutch: i32 = 0,
    aid_auto_blip: i32 = 0,
    has_drs: i32 = 0,
    has_ers: i32 = 0,
    has_kers: i32 = 0,
    kers_max_joules: f32 = 0,
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
};

/// Decode a UTF-16LE (`wchar_t`) buffer into `out` as UTF-8, truncating at the NUL terminator.
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

test "physics scalar offsets match the AC layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Physics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Physics, "gear"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(Physics, "rpms"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Physics, "speed_kmh"));
    try std.testing.expectEqual(@as(usize, 568), @offsetOf(Physics, "local_velocity"));
    try std.testing.expectEqual(@as(usize, 580), @sizeOf(Physics));
}

test "graphics offsets include AC wind fields" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Graphics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Graphics, "current_time"));
    try std.testing.expectEqual(@as(usize, 176), @offsetOf(Graphics, "tyre_compound"));
    try std.testing.expectEqual(@as(usize, 244), @offsetOf(Graphics, "replay_time_multiplier"));
    try std.testing.expectEqual(@as(usize, 284), @offsetOf(Graphics, "mandatory_pit_done"));
    try std.testing.expectEqual(@as(usize, 288), @offsetOf(Graphics, "wind_speed"));
    try std.testing.expectEqual(@as(usize, 292), @offsetOf(Graphics, "wind_direction"));
    try std.testing.expectEqual(@as(usize, 296), @sizeOf(Graphics));
}

test "static offsets match documented AC strings" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Static, "sm_version"));
    try std.testing.expectEqual(@as(usize, 60), @offsetOf(Static, "number_of_sessions"));
    try std.testing.expectEqual(@as(usize, 68), @offsetOf(Static, "car_model"));
    try std.testing.expectEqual(@as(usize, 134), @offsetOf(Static, "track"));
    try std.testing.expectEqual(@as(usize, 200), @offsetOf(Static, "player_name"));
    try std.testing.expectEqual(@as(usize, 456), @offsetOf(Static, "air_temp"));
    try std.testing.expectEqual(@as(usize, 524), @offsetOf(Static, "track_configuration"));
}

test "wcharToUtf8 decodes a UTF-16LE name and stops at NUL" {
    const src = [_]u8{ 'M', 0, 'o', 0, 'n', 0, 'z', 0, 'a', 0, 0, 0, 'X', 0 };
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Monza", wcharToUtf8(&src, &out).?);
}

test "readPacketId reads the leading counter" {
    var phys: Physics = .{};
    phys.packet_id = 99;
    try std.testing.expectEqual(@as(i32, 99), readPacketId(std.mem.asBytes(&phys)).?);
}
