//! Normalized telemetry types shared by the unified manager.

const std = @import("std");
const detector = @import("../detector/root.zig");
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
    detection: detector.Options = .{},
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

test "update status snapshot availability" {
    try std.testing.expect(UpdateStatus.updated.hasSnapshot());
    try std.testing.expect(UpdateStatus.unchanged.hasSnapshot());
    try std.testing.expect(!UpdateStatus.stale.hasSnapshot());
    try std.testing.expect(!UpdateStatus.idle.hasSnapshot());
}
