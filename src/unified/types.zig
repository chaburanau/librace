//! Normalized telemetry types shared by the unified manager.

const std = @import("std");
const detect = @import("../detect/root.zig");
const beamng = @import("../simulators/beamng/root.zig");
const fh6 = @import("../simulators/fh6/root.zig");

pub const UpdateStatus = enum {
    /// No supported simulator process is currently visible.
    idle,
    /// A process exists, but its telemetry transport is not ready yet.
    waiting_for_telemetry,
    /// A fresh telemetry sample was normalized.
    updated,
    /// The client is healthy, but no new sample was available.
    unchanged,
    /// Telemetry could not be copied before the poll deadline.
    stale,
    /// The previous client was torn down. A later update will detect again.
    disconnected,

    /// True when a prior successful normalize is implied by this status.
    /// `.stale` is excluded: the manager may return stale before any snapshot exists.
    pub fn hasSnapshot(self: UpdateStatus) bool {
        return switch (self) {
            .updated, .unchanged => true,
            else => false,
        };
    }
};

pub const Options = struct {
    detection: detect.Options = .{},
    /// Per-attempt wait used by shared-memory clients. Null performs one attempt.
    connect_timeout: ?std.Io.Duration = null,
    connect_retry_interval: std.Io.Duration = std.Io.Duration.fromMilliseconds(200),
    iracing_stale_timeout: ?std.Io.Duration = std.Io.Duration.fromSeconds(30),
    fh6_config: fh6.Config = .{},
    fh6_poll_timeout: std.Io.Timeout = .{ .duration = .{
        .raw = std.Io.Duration.fromMilliseconds(100),
        .clock = .awake,
    } },
    beamng_config: beamng.Config = .{},
    beamng_poll_timeout: std.Io.Timeout = .{ .duration = .{
        .raw = std.Io.Duration.fromMilliseconds(100),
        .clock = .awake,
    } },
};

pub const SessionKind = enum {
    practice,
    qualifying,
    race,
    time_attack,
    other,
};

pub const SessionState = enum {
    garage,
    warmup,
    active,
    paused,
    finished,
    other,
};

pub const Identity = struct {
    track: ?[]const u8 = null,
    car: ?[]const u8 = null,
    driver: ?[]const u8 = null,
};

pub const Vehicle = struct {
    speed_mps: ?f32 = null,
    /// -1 reverse, 0 neutral, 1+ forward gears.
    gear: ?i8 = null,
    engine_rpm: ?f32 = null,
    max_engine_rpm: ?f32 = null,
    fuel_liters: ?f32 = null,
};

pub const Controls = struct {
    /// Pedal values use the normalized 0...1 range.
    throttle: ?f32 = null,
    brake: ?f32 = null,
    clutch: ?f32 = null,
    steering_rad: ?f32 = null,
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Motion = struct {
    acceleration_mps2: ?Vec3 = null,
    /// Vehicle yaw, pitch and roll in radians.
    orientation_rad: ?Vec3 = null,
};

pub const Lap = struct {
    number: ?u32 = null,
    position: ?u16 = null,
    current_time_s: ?f32 = null,
    last_time_s: ?f32 = null,
    best_time_s: ?f32 = null,
    distance_m: ?f32 = null,
};

pub const Session = struct {
    kind: ?SessionKind = null,
    state: ?SessionState = null,
    elapsed_time_s: ?f32 = null,
    remaining_time_s: ?f32 = null,
};

/// Common telemetry subset. Optional fields distinguish unavailable data from zero.
///
/// Identity strings borrow manager-owned storage and remain valid until the next
/// `Manager.update` call or `Manager.deinit`.
pub const Snapshot = struct {
    pid: u32,
    simulator: detect.Simulator,
    identity: Identity = .{},
    vehicle: Vehicle = .{},
    controls: Controls = .{},
    motion: Motion = .{},
    lap: Lap = .{},
    session: Session = .{},
};

test "update status snapshot availability" {
    try std.testing.expect(UpdateStatus.updated.hasSnapshot());
    try std.testing.expect(UpdateStatus.unchanged.hasSnapshot());
    try std.testing.expect(!UpdateStatus.stale.hasSnapshot());
    try std.testing.expect(!UpdateStatus.idle.hasSnapshot());
}
