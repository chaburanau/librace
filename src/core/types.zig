//! Shared telemetry-related types used across simulators.

/// Lifecycle state of a simulator connection.
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    failed,
};

/// Transport mechanism used by a simulator to expose telemetry.
pub const TransportKind = enum {
    mmap,
    udp,
};
