//! Shared telemetry-related types used across simulators.

/// Lifecycle state of a simulator connection.
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    failed,
};

/// Result of a single data poll.
pub const PollStatus = enum {
    ok,
    disconnected,
    stale,
};

/// Transport mechanism used by a simulator to expose telemetry.
pub const TransportKind = enum {
    mmap,
    udp,
};

// All implemented simulators.
pub const Simulator = enum {
    iracing,
    ac,
    acc,
    ace,
    acr,
    ams,
    ams2,
    lmu,
    fh6,
    r3e,
    beamng,
};

// Types of racing session.
pub const SessionKind = enum {
    practice,
    qualifying,
    race,
    time_attack,
    other,
};

// States of racing session.
pub const SessionState = enum {
    garage,
    warmup,
    active,
    paused,
    finished,
    other,
};

// 3D coordinates.
pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
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

pub const Session = struct {
    kind: ?SessionKind = null,
    state: ?SessionState = null,
    elapsed_time_s: ?f32 = null,
    remaining_time_s: ?f32 = null,
};

pub const Lap = struct {
    number: ?u32 = null,
    position: ?u16 = null,
    current_time_s: ?f32 = null,
    last_time_s: ?f32 = null,
    best_time_s: ?f32 = null,
    distance_m: ?f32 = null,
};

pub const Snapshot = struct {
    pid: u32,
    simulator: Simulator,
    identity: Identity = .{},
    vehicle: Vehicle = .{},
    controls: Controls = .{},
    session: Session = .{},
    lap: Lap = .{},
};
