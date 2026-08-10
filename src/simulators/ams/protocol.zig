//! Automobilista (`$pcars$`) shared-memory layout.
//!
//! Reference: Project CARS / Automobilista `SharedMemory.h` (SHARED_MEMORY_VERSION = 5),
//! as used by community clients (CREST, carseour, pcars-api-socket). Automobilista exposes
//! the same `$pcars$` mapping as Project CARS 1.
//!
//! Layout notes:
//! - Named mapping `"$pcars$"` using natural MSVC/C ABI alignment (not packed).
//! - Enable shared memory in the game's hardware / system options.
//! - No `sequence_number` (that arrives with pCars2 / AMS2); torn reads are mitigated by
//!   retrying when version or key player fields change mid-copy.
//! - Strings are UTF-8 `char` buffers. Speeds are m/s; `rpm` is already revolutions/minute.
//! - The 64-entry participant grid sits mid-structure; the client copies it on demand.

const std = @import("std");
const strings = @import("../../core/utils/strings.zig");

pub const mem_map_name = "$pcars$";

pub const shared_memory_version: u32 = 5;
pub const string_length_max: usize = 64;
pub const stored_participants_max: usize = 64;
pub const tyre_max: usize = 4;
pub const vec_max: usize = 3;

pub const mps_to_kmh: f32 = 3.6;

pub const GameState = enum(u32) {
    exited = 0,
    front_end = 1,
    ingame_playing = 2,
    ingame_paused = 3,
    _,

    pub fn label(self: GameState) []const u8 {
        return switch (self) {
            .exited => "Exited",
            .front_end => "Front End",
            .ingame_playing => "Playing",
            .ingame_paused => "Paused",
            _ => "?",
        };
    }
};

pub const SessionState = enum(u32) {
    invalid = 0,
    practice = 1,
    @"test" = 2,
    qualify = 3,
    formation_lap = 4,
    race = 5,
    time_attack = 6,
    _,

    pub fn label(self: SessionState) []const u8 {
        return switch (self) {
            .invalid => "—",
            .practice => "Practice",
            .@"test" => "Test",
            .qualify => "Qualify",
            .formation_lap => "Formation",
            .race => "Race",
            .time_attack => "Time Attack",
            _ => "?",
        };
    }
};

pub const RaceState = enum(u32) {
    invalid = 0,
    not_started = 1,
    racing = 2,
    finished = 3,
    disqualified = 4,
    retired = 5,
    dnf = 6,
    _,

    pub fn label(self: RaceState) []const u8 {
        return switch (self) {
            .invalid => "—",
            .not_started => "Not Started",
            .racing => "Racing",
            .finished => "Finished",
            .disqualified => "DSQ",
            .retired => "Retired",
            .dnf => "DNF",
            _ => "?",
        };
    }
};

pub const PitMode = enum(u32) {
    none = 0,
    driving_into_pits = 1,
    in_pit = 2,
    driving_out_of_pits = 3,
    in_garage = 4,
    _,

    pub fn label(self: PitMode) []const u8 {
        return switch (self) {
            .none => "Track",
            .driving_into_pits => "Entering Pits",
            .in_pit => "In Pit",
            .driving_out_of_pits => "Leaving Pits",
            .in_garage => "Garage",
            _ => "?",
        };
    }
};

pub const FlagColour = enum(u32) {
    none = 0,
    green = 1,
    blue = 2,
    white = 3,
    yellow = 4,
    double_yellow = 5,
    black = 6,
    chequered = 7,
    _,
};

pub const ParticipantInfo = extern struct {
    is_active: bool = false,
    name: [string_length_max]u8 = @splat(0),
    world_position: [vec_max]f32 = @splat(0),
    current_lap_distance: f32 = 0,
    race_position: u32 = 0,
    laps_completed: u32 = 0,
    current_lap: u32 = 0,
    current_sector: u32 = 0,

    pub fn nameUtf8(self: *const ParticipantInfo) []const u8 {
        return strings.cString(&self.name);
    }
};

/// Full `$pcars$` mapping (SHARED_MEMORY_VERSION 5).
pub const Shared = extern struct {
    version: u32 = 0,
    build_version_number: u32 = 0,

    game_state: u32 = 0,
    session_state: u32 = 0,
    race_state: u32 = 0,

    viewed_participant_index: i32 = -1,
    num_participants: i32 = -1,
    participant_info: [stored_participants_max]ParticipantInfo = @splat(.{}),

    unfiltered_throttle: f32 = 0,
    unfiltered_brake: f32 = 0,
    unfiltered_steering: f32 = 0,
    unfiltered_clutch: f32 = 0,

    car_name: [string_length_max]u8 = @splat(0),
    car_class_name: [string_length_max]u8 = @splat(0),

    laps_in_event: u32 = 0,
    track_location: [string_length_max]u8 = @splat(0),
    track_variation: [string_length_max]u8 = @splat(0),
    track_length: f32 = 0,

    lap_invalidated: bool = false,
    best_lap_time: f32 = -1,
    last_lap_time: f32 = 0,
    current_time: f32 = 0,
    split_time_ahead: f32 = -1,
    split_time_behind: f32 = -1,
    split_time: f32 = 0,
    event_time_remaining: f32 = -1,
    personal_fastest_lap_time: f32 = -1,
    world_fastest_lap_time: f32 = -1,
    current_sector1_time: f32 = -1,
    current_sector2_time: f32 = -1,
    current_sector3_time: f32 = -1,
    fastest_sector1_time: f32 = -1,
    fastest_sector2_time: f32 = -1,
    fastest_sector3_time: f32 = -1,
    personal_fastest_sector1_time: f32 = -1,
    personal_fastest_sector2_time: f32 = -1,
    personal_fastest_sector3_time: f32 = -1,
    world_fastest_sector1_time: f32 = -1,
    world_fastest_sector2_time: f32 = -1,
    world_fastest_sector3_time: f32 = -1,

    highest_flag_colour: u32 = 0,
    highest_flag_reason: u32 = 0,

    pit_mode: u32 = 0,
    pit_schedule: u32 = 0,

    car_flags: u32 = 0,
    oil_temp_celsius: f32 = 0,
    oil_pressure_kpa: f32 = 0,
    water_temp_celsius: f32 = 0,
    water_pressure_kpa: f32 = 0,
    fuel_pressure_kpa: f32 = 0,
    fuel_level: f32 = 0,
    fuel_capacity: f32 = 0,
    speed: f32 = 0,
    rpm: f32 = 0,
    max_rpm: f32 = 0,
    brake: f32 = 0,
    throttle: f32 = 0,
    clutch: f32 = 0,
    steering: f32 = 0,
    gear: i32 = 0,
    num_gears: i32 = -1,
    odometer_km: f32 = -1,
    anti_lock_active: bool = false,
    last_opponent_collision_index: i32 = -1,
    last_opponent_collision_magnitude: f32 = 0,
    boost_active: bool = false,
    boost_amount: f32 = 0,

    orientation: [vec_max]f32 = @splat(0),
    local_velocity: [vec_max]f32 = @splat(0),
    world_velocity: [vec_max]f32 = @splat(0),
    angular_velocity: [vec_max]f32 = @splat(0),
    local_acceleration: [vec_max]f32 = @splat(0),
    world_acceleration: [vec_max]f32 = @splat(0),
    extents_centre: [vec_max]f32 = @splat(0),

    tyre_flags: [tyre_max]u32 = @splat(0),
    terrain: [tyre_max]u32 = @splat(0),
    tyre_y: [tyre_max]f32 = @splat(0),
    tyre_rps: [tyre_max]f32 = @splat(0),
    tyre_slip_speed: [tyre_max]f32 = @splat(0),
    tyre_temp: [tyre_max]f32 = @splat(0),
    tyre_grip: [tyre_max]f32 = @splat(0),
    tyre_height_above_ground: [tyre_max]f32 = @splat(0),
    tyre_lateral_stiffness: [tyre_max]f32 = @splat(0),
    tyre_wear: [tyre_max]f32 = @splat(0),
    brake_damage: [tyre_max]f32 = @splat(0),
    suspension_damage: [tyre_max]f32 = @splat(0),
    brake_temp_celsius: [tyre_max]f32 = @splat(0),
    tyre_tread_temp: [tyre_max]f32 = @splat(0),
    tyre_layer_temp: [tyre_max]f32 = @splat(0),
    tyre_carcass_temp: [tyre_max]f32 = @splat(0),
    tyre_rim_temp: [tyre_max]f32 = @splat(0),
    tyre_internal_air_temp: [tyre_max]f32 = @splat(0),

    crash_state: u32 = 0,
    aero_damage: f32 = 0,
    engine_damage: f32 = 0,

    ambient_temperature: f32 = 25,
    track_temperature: f32 = 30,
    rain_density: f32 = 0,
    wind_speed: f32 = 2,
    wind_direction_x: f32 = 0,
    wind_direction_y: f32 = 0,
    cloud_brightness: f32 = 0,

    pub fn gameStateValue(self: *const Shared) GameState {
        return @enumFromInt(self.game_state);
    }

    pub fn sessionStateValue(self: *const Shared) SessionState {
        return @enumFromInt(self.session_state);
    }

    pub fn raceStateValue(self: *const Shared) RaceState {
        return @enumFromInt(self.race_state);
    }

    pub fn pitModeValue(self: *const Shared) PitMode {
        return @enumFromInt(self.pit_mode);
    }

    pub fn flagColourValue(self: *const Shared) FlagColour {
        return @enumFromInt(self.highest_flag_colour);
    }

    pub fn trackLocation(self: *const Shared) []const u8 {
        return strings.cString(&self.track_location);
    }

    pub fn trackVariation(self: *const Shared) []const u8 {
        return strings.cString(&self.track_variation);
    }

    pub fn carName(self: *const Shared) []const u8 {
        return strings.cString(&self.car_name);
    }

    pub fn carClassName(self: *const Shared) []const u8 {
        return strings.cString(&self.car_class_name);
    }

    pub fn speedKmh(self: *const Shared) f32 {
        return self.speed * mps_to_kmh;
    }

    pub fn displayGear(self: *const Shared) i32 {
        return self.gear;
    }

    pub fn viewedParticipant(self: *const Shared) ?*const ParticipantInfo {
        if (self.viewed_participant_index < 0) return null;
        const idx: usize = @intCast(self.viewed_participant_index);
        if (idx >= stored_participants_max) return null;
        return &self.participant_info[idx];
    }

    pub fn playerName(self: *const Shared) []const u8 {
        const p = self.viewedParticipant() orelse return "";
        return p.nameUtf8();
    }
};

pub const shared_size: usize = @sizeOf(Shared);
pub const participant_info_size: usize = @sizeOf(ParticipantInfo);

/// Prefix through `num_participants` (excludes the participant grid).
pub const header_size: usize = @offsetOf(Shared, "participant_info");
/// Offset of the first player/session field after the participant grid.
pub const after_participants_offset: usize = @offsetOf(Shared, "unfiltered_throttle");

pub fn readVersion(view: []const u8) ?u32 {
    if (view.len < 4) return null;
    return std.mem.readInt(u32, view[0..4], .little);
}

pub fn readGameState(view: []const u8) ?u32 {
    const offset = @offsetOf(Shared, "game_state");
    if (view.len < offset + 4) return null;
    return std.mem.readInt(u32, view[offset..][0..4], .little);
}

pub fn readSpeed(view: []const u8) ?f32 {
    const offset = @offsetOf(Shared, "speed");
    if (view.len < offset + 4) return null;
    return @bitCast(std.mem.readInt(u32, view[offset..][0..4], .little));
}

pub fn readRpm(view: []const u8) ?f32 {
    const offset = @offsetOf(Shared, "rpm");
    if (view.len < offset + 4) return null;
    return @bitCast(std.mem.readInt(u32, view[offset..][0..4], .little));
}

test "layout matches pCars1 SharedMemory.h v5 C ABI" {
    try std.testing.expectEqual(@as(usize, 100), participant_info_size);
    try std.testing.expectEqual(@as(usize, 7316), shared_size);
    try std.testing.expectEqual(@as(usize, 28), header_size);
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Shared, "participant_info"));
    try std.testing.expectEqual(@as(usize, 6428), after_participants_offset);
    try std.testing.expectEqual(@as(usize, 6708), @offsetOf(Shared, "lap_invalidated"));
    try std.testing.expectEqual(@as(usize, 6712), @offsetOf(Shared, "best_lap_time"));
    try std.testing.expectEqual(@as(usize, 6884), @offsetOf(Shared, "anti_lock_active"));
    try std.testing.expectEqual(@as(usize, 7312), @offsetOf(Shared, "cloud_brightness"));
}

test "string and unit helpers" {
    var s: Shared = .{};
    @memcpy(s.track_location[0.."Interlagos".len], "Interlagos");
    @memcpy(s.track_variation[0.."GP".len], "GP");
    @memcpy(s.car_name[0.."Stock Car".len], "Stock Car");
    s.speed = 50.0;
    s.gear = 3;
    s.session_state = @intFromEnum(SessionState.race);
    s.viewed_participant_index = 0;
    s.num_participants = 1;
    s.participant_info[0].is_active = true;
    @memcpy(s.participant_info[0].name[0.."Senna".len], "Senna");

    try std.testing.expectEqualStrings("Interlagos", s.trackLocation());
    try std.testing.expectEqualStrings("GP", s.trackVariation());
    try std.testing.expectEqualStrings("Stock Car", s.carName());
    try std.testing.expectEqualStrings("Senna", s.playerName());
    try std.testing.expectApproxEqAbs(@as(f32, 180.0), s.speedKmh(), 0.01);
    try std.testing.expectEqual(@as(i32, 3), s.displayGear());
    try std.testing.expectEqual(SessionState.race, s.sessionStateValue());
    try std.testing.expectEqualStrings("Race", s.sessionStateValue().label());
}

test "version and field readers" {
    var bytes: [shared_size]u8 = undefined;
    @memset(&bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 5, .little);
    std.mem.writeInt(u32, bytes[@offsetOf(Shared, "game_state")..][0..4], 2, .little);
    std.mem.writeInt(u32, bytes[@offsetOf(Shared, "speed")..][0..4], @as(u32, @bitCast(@as(f32, 27.5))), .little);
    std.mem.writeInt(u32, bytes[@offsetOf(Shared, "rpm")..][0..4], @as(u32, @bitCast(@as(f32, 7000.0))), .little);

    try std.testing.expectEqual(@as(u32, 5), readVersion(&bytes).?);
    try std.testing.expectEqual(@as(u32, 2), readGameState(&bytes).?);
    try std.testing.expectApproxEqAbs(@as(f32, 27.5), readSpeed(&bytes).?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7000.0), readRpm(&bytes).?, 0.001);
}
