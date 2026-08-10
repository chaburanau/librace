//! BeamNG.drive OutGauge UDP packet layout.
//!
//! Reference: [BeamNG Protocols](https://documentation.beamng.com/modding/protocols/)
//! (OutGauge; Live For Speed–compatible; last reviewed Jan 2025).
//!
//! Layout notes:
//! - Little-endian packed datagram; 92 bytes without optional `id`, 96 with it.
//! - BeamNG hardcodes several LFS fields (`time` = 0, `car` = `"beam"`, …).
//! - Gear encoding: 0 = reverse, 1 = neutral, 2+ = forward gears.
//! - Speed is meters per second; pedals and fuel are 0…1.
//! - Disable MotionSim on the same port (or filter it); MotionSim packets begin with `"BNG1"`.

const std = @import("std");
const strings = @import("../../core/utils/strings.zig");

/// Default listener port. Must match Options → Other → Protocols → OutGauge UDP port.
pub const default_port: u16 = 4444;

/// Wire size when OutGauge ID is configured in the game.
pub const packet_size: usize = 96;
/// Wire size when OutGauge ID is left unset.
pub const packet_size_without_id: usize = 92;

/// Bits for [`OutGaugePacket.flags`].
pub const Flags = struct {
    pub const shift: u16 = 1; // N/A in BeamNG
    pub const ctrl: u16 = 2; // N/A in BeamNG
    pub const turbo: u16 = 8192; // show turbo gauge
    pub const km: u16 = 16384; // if not set, user prefers miles
    pub const bar: u16 = 32768; // if not set, user prefers PSI
};

/// Bits for [`OutGaugePacket.dash_lights`] / [`OutGaugePacket.show_lights`].
pub const DashLight = struct {
    pub const shift: u32 = 1 << 0;
    pub const fullbeam: u32 = 1 << 1;
    pub const handbrake: u32 = 1 << 2;
    pub const pitspeed: u32 = 1 << 3; // N/A in BeamNG
    pub const tc: u32 = 1 << 4;
    pub const signal_l: u32 = 1 << 5;
    pub const signal_r: u32 = 1 << 6;
    pub const signal_any: u32 = 1 << 7; // N/A in BeamNG
    pub const oilwarn: u32 = 1 << 8;
    pub const battery: u32 = 1 << 9;
    pub const abs: u32 = 1 << 10;
    pub const spare: u32 = 1 << 11; // N/A in BeamNG
};

/// Wire layout of a single BeamNG OutGauge datagram (with optional trailing `id`).
pub const OutGaugePacket = extern struct {
    /// Milliseconds (BeamNG: hardcoded 0).
    time: u32 = 0,
    /// Car name (BeamNG: fixed `"beam"`).
    car: [4]u8 = .{ 'b', 'e', 'a', 'm' },
    flags: u16 = 0,
    /// Reverse: 0, Neutral: 1, First: 2, …
    gear: u8 = 1,
    /// Viewed player id (BeamNG: hardcoded 0).
    plid: u8 = 0,
    /// m/s
    speed: f32 = 0,
    rpm: f32 = 0,
    /// BAR
    turbo: f32 = 0,
    /// °C
    eng_temp: f32 = 0,
    /// 0…1
    fuel: f32 = 0,
    /// BAR (BeamNG: hardcoded 0).
    oil_pressure: f32 = 0,
    /// °C
    oil_temp: f32 = 0,
    dash_lights: u32 = 0,
    show_lights: u32 = 0,
    /// 0…1
    throttle: f32 = 0,
    /// 0…1
    brake: f32 = 0,
    /// 0…1
    clutch: f32 = 0,
    /// Usually fuel (BeamNG: hardcoded empty).
    display1: [16]u8 = .{0} ** 16,
    /// Usually settings (BeamNG: hardcoded empty).
    display2: [16]u8 = .{0} ** 16,
    /// Present only when OutGauge ID is set in the game; otherwise 0 after decode.
    id: i32 = 0,

    pub fn speedKmh(self: *const OutGaugePacket) f32 {
        return self.speed * 3.6;
    }

    pub fn speedMph(self: *const OutGaugePacket) f32 {
        return self.speed * 2.2369363;
    }

    /// Dashboard-friendly gear: -1 reverse, 0 neutral, 1+ forward.
    pub fn displayGear(self: *const OutGaugePacket) i32 {
        return switch (self.gear) {
            0 => -1,
            1 => 0,
            else => @as(i32, @intCast(self.gear)) - 1,
        };
    }

    pub fn prefersKm(self: *const OutGaugePacket) bool {
        return self.flags & Flags.km != 0;
    }

    pub fn prefersBar(self: *const OutGaugePacket) bool {
        return self.flags & Flags.bar != 0;
    }

    pub fn hasTurboGauge(self: *const OutGaugePacket) bool {
        return self.flags & Flags.turbo != 0;
    }

    pub fn lightOn(self: *const OutGaugePacket, mask: u32) bool {
        return self.show_lights & mask != 0;
    }

    pub fn lightAvailable(self: *const OutGaugePacket, mask: u32) bool {
        return self.dash_lights & mask != 0;
    }

    /// NUL-terminated ASCII from `car` (BeamNG always `"beam"`).
    pub fn carName(self: *const OutGaugePacket) []const u8 {
        return strings.cString(&self.car);
    }

    pub fn display1Text(self: *const OutGaugePacket) []const u8 {
        return strings.cString(&self.display1);
    }

    pub fn display2Text(self: *const OutGaugePacket) []const u8 {
        return strings.cString(&self.display2);
    }
};

/// Copy `bytes` into `dest`. Accepts 92- or 96-byte OutGauge datagrams.
pub fn decodePacket(bytes: []const u8, dest: *OutGaugePacket) bool {
    if (bytes.len < packet_size_without_id) return false;
    // MotionSim and other BeamNG protocols may share a port; reject their magic.
    if (bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], "BNG1")) return false;

    if (bytes.len >= packet_size) {
        @memcpy(std.mem.asBytes(dest), bytes[0..packet_size]);
        return true;
    }
    if (bytes.len == packet_size_without_id) {
        @memcpy(std.mem.asBytes(dest)[0..packet_size_without_id], bytes);
        dest.id = 0;
        return true;
    }
    return false;
}

test "OutGaugePacket matches official 96-byte layout" {
    try std.testing.expectEqual(@as(usize, 96), @sizeOf(OutGaugePacket));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(OutGaugePacket, "time"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(OutGaugePacket, "car"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(OutGaugePacket, "flags"));
    try std.testing.expectEqual(@as(usize, 10), @offsetOf(OutGaugePacket, "gear"));
    try std.testing.expectEqual(@as(usize, 11), @offsetOf(OutGaugePacket, "plid"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(OutGaugePacket, "speed"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(OutGaugePacket, "rpm"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(OutGaugePacket, "throttle"));
    try std.testing.expectEqual(@as(usize, 60), @offsetOf(OutGaugePacket, "display1"));
    try std.testing.expectEqual(@as(usize, 76), @offsetOf(OutGaugePacket, "display2"));
    try std.testing.expectEqual(@as(usize, 92), @offsetOf(OutGaugePacket, "id"));
}

test "decodePacket accepts 92- and 96-byte datagrams" {
    var raw92: [packet_size_without_id]u8 = .{0} ** packet_size_without_id;
    @memcpy(raw92[4..8], "beam");
    raw92[10] = 3; // 2nd gear
    std.mem.writeInt(u32, raw92[12..16], @as(u32, @bitCast(@as(f32, 25.0))), .little);
    std.mem.writeInt(u32, raw92[16..20], @as(u32, @bitCast(@as(f32, 4200))), .little);
    std.mem.writeInt(u32, raw92[48..52], @as(u32, @bitCast(@as(f32, 0.5))), .little);

    var pkt: OutGaugePacket = .{};
    try std.testing.expect(decodePacket(&raw92, &pkt));
    try std.testing.expectEqualStrings("beam", pkt.carName());
    try std.testing.expectEqual(@as(i32, 2), pkt.displayGear());
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), pkt.speedKmh(), 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 4200), pkt.rpm, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), pkt.throttle, 0.001);
    try std.testing.expectEqual(@as(i32, 0), pkt.id);

    var raw96: [packet_size]u8 = .{0} ** packet_size;
    @memcpy(raw96[0..packet_size_without_id], &raw92);
    std.mem.writeInt(i32, raw96[92..96], 7, .little);
    try std.testing.expect(decodePacket(&raw96, &pkt));
    try std.testing.expectEqual(@as(i32, 7), pkt.id);
}

test "decodePacket rejects MotionSim magic" {
    var raw: [packet_size]u8 = .{0} ** packet_size;
    @memcpy(raw[0..4], "BNG1");
    var pkt: OutGaugePacket = .{};
    try std.testing.expect(!decodePacket(&raw, &pkt));
}
