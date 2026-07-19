//! UDP telemetry transport primitives.
//!
//! Some simulators broadcast telemetry over UDP (often alongside shared memory).
//! Per-simulator packet layouts and ports live in `simulators/`.
//!
//! Uses `std.Io.net`; receive behavior is controlled with [`std.Io.Timeout`].

const std = @import("std");
const net = std.Io.net;

/// UDP listener configuration.
pub const Config = struct {
    /// Local bind address. Use `"0.0.0.0"` to listen on all interfaces.
    address: []const u8 = "0.0.0.0",
    /// UDP port to listen on.
    port: u16,
};

/// Bound UDP socket for receiving game telemetry datagrams.
pub const UdpListener = struct {
    socket: net.Socket,
    closed: bool = false,

    pub const OpenError = error{
        InvalidAddress,
    } || net.IpAddress.BindError;

    pub fn open(io: std.Io, config: Config) OpenError!UdpListener {
        const addr = try parseBindAddress(config.address, config.port);
        const socket = try addr.bind(io, .{ .mode = .dgram, .protocol = .udp });
        return .{ .socket = socket };
    }

    pub fn close(self: *UdpListener, io: std.Io) void {
        if (self.closed) return;
        self.closed = true;
        self.socket.close(io);
    }

    /// Receives a datagram according to `timeout`. Payload is written into
    /// `buffer`; the returned slice aliases `buffer`.
    pub fn recv(
        self: *const UdpListener,
        io: std.Io,
        buffer: []u8,
        timeout: std.Io.Timeout,
    ) net.Socket.ReceiveTimeoutError!net.IncomingMessage {
        return self.socket.receiveTimeout(io, buffer, timeout);
    }
};

fn parseBindAddress(address: []const u8, port: u16) UdpListener.OpenError!net.IpAddress {
    if (std.mem.eql(u8, address, "0.0.0.0")) {
        return .{ .ip4 = .unspecified(port) };
    }
    return net.IpAddress.parse(address, port) catch return error.InvalidAddress;
}
