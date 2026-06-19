//! Assetto Corsa Rally shared-memory layout.
//!
//! Reference: the classic Assetto Corsa "Shared Memory Reference" (Kunos, AC 1.5+) and the
//! widely used community bindings (mdjarv/assettocorsasharedmemory, acc-extension-apps
//! `sim_info.py`). AC Rally publishes under the same three classic AC tag names —
//! `Local\\acpmf_physics`, `Local\\acpmf_graphics`, `Local\\acpmf_static` — and reuses the
//! original AC1 `SPageFile*` struct layout (NOT the renamed/extended AC Evo `acevo_pmf_*`
//! layout, which uses 1-byte `char` strings and embedded sub-structs).
//!
//! Layout notes:
//! - The C structs are declared `#pragma pack(4)`. None of the AC1 fields use a type whose
//!   natural alignment exceeds 4 (no `double`/`int64`), so a plain Zig `extern struct` already
//!   matches the C layout — including the compiler-inserted padding after odd-length `wchar_t`
//!   arrays (e.g. before the float that follows `tyre_compound`).
//! - Strings are `wchar_t` (UTF-16LE, 2 bytes per code unit on Windows). They are modelled here
//!   as `[N]u16`; decode them with `catalog.decodeWString` / `wcharToUtf8`.
//! - All scalars are little-endian (Windows/x86-64).
//! - Pages are single, in-place structs (not ring-buffered). `packetId` (offset 0 on the
//!   physics and graphics pages) increments on each update and is used to detect torn reads.

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

/// Race flag currently shown to the driver (`SPageFileGraphic.flag`, classic AC ordering).
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
///
/// Fields follow the AC1 `SPageFilePhysics` order; the trailing comments mark the AC version
/// each block was introduced in. AC Rally maps the same prefix.
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
    // since 1.5
    turbo_boost: f32 = 0,
    ballast: f32 = 0,
    air_density: f32 = 0,
    // since 1.6
    air_temp: f32 = 0,
    road_temp: f32 = 0,
    local_angular_vel: [3]f32 = .{ 0, 0, 0 },
    final_ff: f32 = 0,
    // since 1.7
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
    // since 1.10
    clutch: f32 = 0,
    tyre_temp_i: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_temp_m: [4]f32 = .{ 0, 0, 0, 0 },
    tyre_temp_o: [4]f32 = .{ 0, 0, 0, 0 },
    // since 1.10.2
    is_ai_controlled: i32 = 0,
    // since 1.11
    tyre_contact_point: [4][3]f32 = @splat(@splat(0)),
    tyre_contact_normal: [4][3]f32 = @splat(@splat(0)),
    tyre_contact_heading: [4][3]f32 = @splat(@splat(0)),
    brake_bias: f32 = 0,
    // since 1.12
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
    // since 1.5
    is_in_pit_lane: i32 = 0,
    surface_grip: f32 = 0,
    // since 1.13
    mandatory_pit_done: i32 = 0,

    pub fn statusValue(self: *const Graphics) Status {
        return @enumFromInt(self.status);
    }

    pub fn sessionValue(self: *const Graphics) SessionType {
        return @enumFromInt(self.session);
    }

    pub fn flagValue(self: *const Graphics) FlagType {
        return @enumFromInt(self.flag);
    }

    /// Synthesised location label (AC1 has no `carLocation` enum, only pit booleans).
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
    // since 1.5
    max_turbo_boost: f32 = 0,
    deprecated_1: f32 = 0,
    deprecated_2: f32 = 0,
    penalties_enabled: i32 = 0,
    aid_fuel_rate: f32 = 0,
    aid_tire_rate: f32 = 0,
    aid_mechanical_damage: f32 = 0,
    aid_allow_tyre_blankets: i32 = 0,
    aid_stability: f32 = 0,
    aid_auto_clutch: i32 = 0,
    aid_auto_blip: i32 = 0,
    // since 1.7.1
    has_drs: i32 = 0,
    has_ers: i32 = 0,
    has_kers: i32 = 0,
    kers_max_joules: f32 = 0,
    engine_brake_settings_count: i32 = 0,
    ers_power_controller_count: i32 = 0,
    // since 1.7.2
    track_spline_length: f32 = 0,
    track_configuration: [15]u16 = @splat(0),
    // since 1.10.2
    ers_max_j: f32 = 0,
    // since 1.13
    is_timed_race: i32 = 0,
    has_extra_lap: i32 = 0,
    car_skin: [33]u16 = @splat(0),
    reversed_grid_positions: i32 = 0,
    pit_window_start: i32 = 0,
    pit_window_end: i32 = 0,
};

/// Decode a UTF-16LE (`wchar_t`) buffer into `out` as UTF-8, truncating at the NUL terminator.
/// `src_bytes` is the raw little-endian byte view of an `[N]u16` field. Returns the written
/// UTF-8 slice (borrowing `out`), or null when conversion fails.
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

test "physics scalar offsets match the AC1 layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Physics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Physics, "gear"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(Physics, "rpms"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Physics, "speed_kmh"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Physics, "velocity"));
    try std.testing.expectEqual(@as(usize, 44), @offsetOf(Physics, "acc_g"));
    try std.testing.expectEqual(@as(usize, 200), @offsetOf(Physics, "drs"));
    try std.testing.expectEqual(@as(usize, 568), @offsetOf(Physics, "local_velocity"));
    try std.testing.expectEqual(@as(usize, 580), @sizeOf(Physics));
}

test "graphics offsets account for wchar string sizes" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Graphics, "packet_id"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Graphics, "status"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Graphics, "session"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Graphics, "current_time"));
    try std.testing.expectEqual(@as(usize, 132), @offsetOf(Graphics, "completed_laps"));
    try std.testing.expectEqual(@as(usize, 176), @offsetOf(Graphics, "tyre_compound"));
    // 2 bytes of pad follow the 66-byte tyre_compound before the next f32.
    try std.testing.expectEqual(@as(usize, 244), @offsetOf(Graphics, "replay_time_multiplier"));
}

test "static string offsets land on the documented boundaries" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Static, "sm_version"));
    try std.testing.expectEqual(@as(usize, 60), @offsetOf(Static, "number_of_sessions"));
    try std.testing.expectEqual(@as(usize, 68), @offsetOf(Static, "car_model"));
    try std.testing.expectEqual(@as(usize, 134), @offsetOf(Static, "track"));
    try std.testing.expectEqual(@as(usize, 200), @offsetOf(Static, "player_name"));
}

test "wcharToUtf8 decodes a UTF-16LE name and stops at NUL" {
    // "Spa" as UTF-16LE followed by a terminator and trailing garbage.
    const src = [_]u8{ 'S', 0, 'p', 0, 'a', 0, 0, 0, 'X', 0 };
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Spa", wcharToUtf8(&src, &out).?);
}

test "readPacketId reads the leading counter" {
    var phys: Physics = .{};
    phys.packet_id = 99;
    try std.testing.expectEqual(@as(i32, 99), readPacketId(std.mem.asBytes(&phys)).?);
}
