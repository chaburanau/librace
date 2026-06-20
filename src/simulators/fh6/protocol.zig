//! Forza Horizon 6 UDP "Data Out" packet layout.
//!
//! Reference: [Forza Horizon 6 Data Out Documentation](https://support.forza.net/hc/en-us/articles/51744149102611-Forza-Horizon-6-Data-Out-Documentation)
//!
//! Layout notes:
//! - Fixed 324-byte little-endian datagram (Horizon dash format).
//! - FH6 adds `car_group`, `smashable_vel_diff`, and `smashable_mass` after `num_cylinders`.
//! - Gear encoding: 0 = reverse, 1 = neutral, 2+ = forward gears.
//! - Speed is meters per second; inputs are 0–255 except steer/driving-line fields (S8).

const std = @import("std");

/// Default listener port. Must match FH6 Settings → HUD and Gameplay → Data Out IP Port.
/// Avoid 5200–5300 (the game binds its outgoing socket in that range).
pub const default_port: u16 = 20066;

pub const packet_size: usize = 324;

pub const CarClass = enum(i32) {
    d = 0,
    c = 1,
    b = 2,
    a = 3,
    s1 = 4,
    s2 = 5,
    r = 6,
    x = 7,
    _,

    pub fn label(self: CarClass) []const u8 {
        return switch (self) {
            .d => "D",
            .c => "C",
            .b => "B",
            .a => "A",
            .s1 => "S1",
            .s2 => "S2",
            .r => "R",
            .x => "X",
            _ => "?",
        };
    }
};

pub const DrivetrainType = enum(i32) {
    fwd = 0,
    rwd = 1,
    awd = 2,
    _,

    pub fn label(self: DrivetrainType) []const u8 {
        return switch (self) {
            .fwd => "FWD",
            .rwd => "RWD",
            .awd => "AWD",
            _ => "?",
        };
    }
};

/// Wire layout of a single FH6 Data Out datagram.
pub const DashPacket = extern struct {
    is_race_on: i32 = 0,
    timestamp_ms: u32 = 0,
    engine_max_rpm: f32 = 0,
    engine_idle_rpm: f32 = 0,
    current_engine_rpm: f32 = 0,
    acceleration_x: f32 = 0,
    acceleration_y: f32 = 0,
    acceleration_z: f32 = 0,
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    velocity_z: f32 = 0,
    angular_velocity_x: f32 = 0,
    angular_velocity_y: f32 = 0,
    angular_velocity_z: f32 = 0,
    yaw: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    normalized_suspension_travel_front_left: f32 = 0,
    normalized_suspension_travel_front_right: f32 = 0,
    normalized_suspension_travel_rear_left: f32 = 0,
    normalized_suspension_travel_rear_right: f32 = 0,
    tire_slip_ratio_front_left: f32 = 0,
    tire_slip_ratio_front_right: f32 = 0,
    tire_slip_ratio_rear_left: f32 = 0,
    tire_slip_ratio_rear_right: f32 = 0,
    wheel_rotation_speed_front_left: f32 = 0,
    wheel_rotation_speed_front_right: f32 = 0,
    wheel_rotation_speed_rear_left: f32 = 0,
    wheel_rotation_speed_rear_right: f32 = 0,
    wheel_on_rumble_strip_front_left: i32 = 0,
    wheel_on_rumble_strip_front_right: i32 = 0,
    wheel_on_rumble_strip_rear_left: i32 = 0,
    wheel_on_rumble_strip_rear_right: i32 = 0,
    wheel_in_puddle_front_left: i32 = 0,
    wheel_in_puddle_front_right: i32 = 0,
    wheel_in_puddle_rear_left: i32 = 0,
    wheel_in_puddle_rear_right: i32 = 0,
    surface_rumble_front_left: f32 = 0,
    surface_rumble_front_right: f32 = 0,
    surface_rumble_rear_left: f32 = 0,
    surface_rumble_rear_right: f32 = 0,
    tire_slip_angle_front_left: f32 = 0,
    tire_slip_angle_front_right: f32 = 0,
    tire_slip_angle_rear_left: f32 = 0,
    tire_slip_angle_rear_right: f32 = 0,
    tire_combined_slip_front_left: f32 = 0,
    tire_combined_slip_front_right: f32 = 0,
    tire_combined_slip_rear_left: f32 = 0,
    tire_combined_slip_rear_right: f32 = 0,
    suspension_travel_meters_front_left: f32 = 0,
    suspension_travel_meters_front_right: f32 = 0,
    suspension_travel_meters_rear_left: f32 = 0,
    suspension_travel_meters_rear_right: f32 = 0,
    car_ordinal: i32 = 0,
    car_class: i32 = 0,
    car_performance_index: i32 = 0,
    drivetrain_type: i32 = 0,
    num_cylinders: i32 = 0,
    car_group: u32 = 0,
    smashable_vel_diff: f32 = 0,
    smashable_mass: f32 = 0,
    position_x: f32 = 0,
    position_y: f32 = 0,
    position_z: f32 = 0,
    speed: f32 = 0,
    power: f32 = 0,
    torque: f32 = 0,
    tire_temp_front_left: f32 = 0,
    tire_temp_front_right: f32 = 0,
    tire_temp_rear_left: f32 = 0,
    tire_temp_rear_right: f32 = 0,
    boost: f32 = 0,
    fuel: f32 = 0,
    distance_traveled: f32 = 0,
    best_lap: f32 = 0,
    last_lap: f32 = 0,
    current_lap: f32 = 0,
    current_race_time: f32 = 0,
    lap_number: u16 = 0,
    race_position: u8 = 0,
    accel: u8 = 0,
    brake: u8 = 0,
    clutch: u8 = 0,
    hand_brake: u8 = 0,
    gear: u8 = 0,
    steer: i8 = 0,
    normalized_driving_line: i8 = 0,
    normalized_ai_brake_difference: i8 = 0,

    pub fn speedKmh(self: *const DashPacket) f32 {
        return self.speed * 3.6;
    }

    pub fn carClassValue(self: *const DashPacket) CarClass {
        return @enumFromInt(self.car_class);
    }

    pub fn drivetrainValue(self: *const DashPacket) DrivetrainType {
        return @enumFromInt(self.drivetrain_type);
    }

    /// Dashboard-friendly gear: -1 reverse, 0 neutral, 1+ forward.
    pub fn displayGear(self: *const DashPacket) i32 {
        return switch (self.gear) {
            0 => -1,
            1 => 0,
            else => @as(i32, @intCast(self.gear)) - 1,
        };
    }

    pub fn formatCarSummary(self: *const DashPacket, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s} {d} #{d}", .{
            self.carClassValue().label(),
            self.car_performance_index,
            self.car_ordinal,
        }) catch "?";
    }

    pub fn sessionLabel(self: *const DashPacket) []const u8 {
        return if (self.is_race_on != 0) "driving" else "idle";
    }
};

/// Copy `bytes` into `dest`, requiring at least [`packet_size`] bytes.
pub fn decodePacket(bytes: []const u8, dest: *DashPacket) bool {
    if (bytes.len < packet_size) return false;
    @memcpy(std.mem.asBytes(dest), bytes[0..packet_size]);
    return true;
}

test "DashPacket matches official 324-byte layout" {
    try std.testing.expectEqual(@as(usize, 324), @sizeOf(DashPacket));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(DashPacket, "is_race_on"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(DashPacket, "engine_max_rpm"));
    try std.testing.expectEqual(@as(usize, 232), @offsetOf(DashPacket, "car_group"));
    try std.testing.expectEqual(@as(usize, 244), @offsetOf(DashPacket, "position_x"));
    try std.testing.expectEqual(@as(usize, 256), @offsetOf(DashPacket, "speed"));
    try std.testing.expectEqual(@as(usize, 319), @offsetOf(DashPacket, "gear"));
    try std.testing.expectEqual(@as(usize, 322), @offsetOf(DashPacket, "normalized_ai_brake_difference"));
}

test "decodePacket copies a full datagram" {
    var raw: [packet_size]u8 = .{0} ** packet_size;
    std.mem.writeInt(i32, raw[0..4], 1, .little);
    std.mem.writeInt(u32, raw[4..8], 42, .little);
    std.mem.writeInt(u32, raw[16..20], @as(u32, @bitCast(@as(f32, 6500))), .little);
    std.mem.writeInt(u32, raw[256..260], @as(u32, @bitCast(@as(f32, 55.5))), .little);
    raw[319] = 4;

    var pkt: DashPacket = .{};
    try std.testing.expect(decodePacket(&raw, &pkt));
    try std.testing.expectEqual(@as(i32, 1), pkt.is_race_on);
    try std.testing.expectEqual(@as(u32, 42), pkt.timestamp_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 6500), pkt.current_engine_rpm, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 199.8), pkt.speedKmh(), 0.1);
    try std.testing.expectEqual(@as(i32, 3), pkt.displayGear());
}
