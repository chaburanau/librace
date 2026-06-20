//! UDP telemetry transport primitives.
//!
//! Some simulators broadcast telemetry over UDP (often alongside shared memory).
//! Per-simulator packet layouts and ports live in `simulators/`.
//!
//! Windows uses Winsock directly because `std.Io.net.Socket.receiveTimeout` relies on
//! concurrent batch I/O that is not implemented for UDP receive on Windows.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const ws2 = windows.ws2_32;

/// UDP listener configuration.
pub const Config = struct {
    /// Local bind address. Use `"0.0.0.0"` to listen on all interfaces.
    address: []const u8 = "0.0.0.0",
    /// UDP port to listen on.
    port: u16,
};

/// Bound UDP socket for receiving game telemetry datagrams.
pub const UdpListener = struct {
    socket: Socket = invalid_socket,
    bound_port: u16 = 0,

    pub const OpenError = error{
        UnsupportedPlatform,
        InvalidAddress,
        BindFailed,
        AddressInUse,
    };

    pub fn open(config: Config) OpenError!UdpListener {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
        try ensureWsaStarted();

        const sock = WSASocketW(
            ws2.AF.INET,
            ws2.SOCK.DGRAM,
            ws2.IPPROTO.UDP,
            null,
            0,
            0,
        );
        if (sock == invalid_socket) return error.BindFailed;

        var yes: i32 = 1;
        _ = setsockopt(
            sock,
            ws2.SOL.SOCKET,
            ws2.SO.REUSEADDR,
            @ptrCast(&yes),
            @sizeOf(i32),
        );

        var addr = try parseBindAddress(config.address, config.port);
        if (bind(sock, @ptrCast(&addr), @sizeOf(ws2.sockaddr.in)) == socket_error) {
            _ = closesocket(sock);
            return error.AddressInUse;
        }

        var mode: u32 = 1;
        _ = ioctlsocket(sock, fionbio, &mode);

        return .{ .socket = sock, .bound_port = config.port };
    }

    pub fn close(self: *UdpListener) void {
        if (self.socket != invalid_socket) {
            _ = closesocket(self.socket);
            self.socket = invalid_socket;
        }
    }

    pub const RecvError = error{
        RecvFailed,
    };

    /// Non-blocking receive. Returns `null` when no datagram is waiting.
    pub fn tryRecv(self: *UdpListener, buffer: []u8) RecvError!?usize {
        const n = recvfrom(
            self.socket,
            buffer.ptr,
            @intCast(buffer.len),
            0,
            null,
            null,
        );
        if (n == socket_error) {
            if (WSAGetLastError() == wsaewouldblock) return null;
            return error.RecvFailed;
        }
        return @intCast(n);
    }
};

const Socket = usize;
const invalid_socket: Socket = std.math.maxInt(Socket);
const socket_error: c_int = -1;
const fionbio: c_ulong = 0x8004667e;
const wsaewouldblock: u32 = 10035;

var wsa_started = false;

fn ensureWsaStarted() UdpListener.OpenError!void {
    if (wsa_started) return;
    var data: WSADATA = undefined;
    if (WSAStartup(0x0202, &data) != 0) return error.BindFailed;
    wsa_started = true;
}

fn parseBindAddress(address: []const u8, port: u16) UdpListener.OpenError!ws2.sockaddr.in {
    var bytes: [4]u8 = .{ 0, 0, 0, 0 };
    if (!std.mem.eql(u8, address, "0.0.0.0")) {
        const ip4 = std.Io.net.Ip4Address.parse(address, 0) catch return error.InvalidAddress;
        bytes = ip4.bytes;
    }
    return .{
        .family = ws2.AF.INET,
        .port = htons(port),
        .addr = @bitCast(bytes),
        .zero = .{0} ** 8,
    };
}

const WSADATA = extern struct {
    version: u16,
    high_version: u16,
    max_sockets: u16,
    max_udp_datagram: u16,
    vendor_info: [257]u8,
    description: [257]u8,
    status: [129]u8,
};

extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSADATA) callconv(.winapi) c_int;
extern "ws2_32" fn WSASocketW(
    af: i32,
    type_: i32,
    protocol: i32,
    protocol_info: ?*anyopaque,
    group: u32,
    flags: u32,
) callconv(.winapi) Socket;
extern "ws2_32" fn bind(sock: Socket, addr: *const anyopaque, addrlen: c_int) callconv(.winapi) c_int;
extern "ws2_32" fn setsockopt(
    sock: Socket,
    level: i32,
    optname: i32,
    optval: ?*anyopaque,
    optlen: i32,
) callconv(.winapi) c_int;
extern "ws2_32" fn ioctlsocket(sock: Socket, cmd: c_ulong, argp: *u32) callconv(.winapi) c_int;
extern "ws2_32" fn recvfrom(
    sock: Socket,
    buf: [*]u8,
    len: c_int,
    flags: c_int,
    from: ?*anyopaque,
    fromlen: ?*c_int,
) callconv(.winapi) c_int;
extern "ws2_32" fn closesocket(sock: Socket) callconv(.winapi) c_int;
extern "ws2_32" fn WSAGetLastError() callconv(.winapi) u32;
extern "ws2_32" fn htons(hostshort: u16) callconv(.winapi) u16;

test "UdpListener open and close" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var listener = try UdpListener.open(.{ .port = 0 });
    defer listener.close();
}
