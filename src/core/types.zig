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
    memory_mapped,
    udp,
    /// Simulators that expose telemetry through more than one channel.
    hybrid,
    /// Reserved for simulators with bespoke protocols (WebSocket, TCP, etc.).
    custom,
};
