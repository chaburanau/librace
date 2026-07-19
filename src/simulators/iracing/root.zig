//! iRacing telemetry via the iRacing SDK shared-memory interface.
//!
//! Transport: memory-mapped file (`Local\\IRSDKMemMapFileName` on Windows).
//! Protocol: IRSDK v2 — variable catalog + triple-buffered telemetry rows.

const core = @import("../../core/root.zig");
const std = @import("std");

const client = @import("client.zig");
const protocol = @import("protocol.zig");
const session = @import("session.zig");
pub const commands = @import("commands.zig");
pub const enums = @import("enums.zig");

pub const keys = @import("keys.zig");

pub const name = "iRacing";
pub const transport = core.types.TransportKind.mmap;

pub const ConnectError = client.ConnectError;
pub const ConnectOptions = struct {
    /// Omitted/null means one connection attempt.
    timeout: ?std.Io.Duration = null,
    retry_interval: std.Io.Duration = std.Io.Duration.fromMilliseconds(200),
    /// Treat an otherwise connected simulator as stale after no new telemetry.
    /// Set to null to disable liveness timeout checks.
    stale_timeout: ?std.Io.Duration = std.Io.Duration.fromSeconds(30),
};
pub const PollStatus = client.PollStatus;
pub const Client = client.Client;
pub const HeaderView = client.HeaderView;
pub const HeaderStatus = client.HeaderStatus;
pub const SessionView = client.SessionView;
pub const SessionSnapshot = client.SessionSnapshot;
pub const SessionParseError = client.SessionParseError;
pub const SessionQueryError = session.QueryError;
pub const SessionScalarError = session.ScalarError;
pub const SessionScalarKind = session.ScalarKind;
pub const SessionScalar = session.Scalar;
pub const SessionPathSegment = session.PathSegment;
pub const SessionSelection = session.Selection;
pub const SessionMatchValue = session.MatchValue;
pub const VariablesView = client.VariablesView;
pub const VariableError = client.VariableError;
pub const VariableType = client.VariableType;
pub const Variable = client.Variable;
pub const VariableDescriptor = client.VariableDescriptor;
pub const DescriptorIterator = client.DescriptorIterator;
pub const VariableValue = client.VariableValue;
pub const VariableArrayView = client.VariableArrayView;
pub const Controller = commands.Controller;
pub const Command = commands.Command;

pub const mem_map_name = protocol.mem_map_name;

pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: ConnectOptions) ConnectError!Client {
    var result = try core.connect.retry(
        Client,
        ConnectError,
        std.mem.Allocator,
        io,
        allocator,
        .{
            .timeout = options.timeout,
            .retry_interval = options.retry_interval,
        },
        Client.connect,
        isRetryableConnectError,
    );
    result.configureLiveness(io, options.stale_timeout);
    return result;
}

fn isRetryableConnectError(err: ConnectError) bool {
    return switch (err) {
        error.NotFound, error.MapFailed, error.InvalidHeader => true,
        else => false,
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("client.zig");
    _ = @import("protocol.zig");
    _ = @import("session.zig");
    _ = @import("keys.zig");
    _ = commands;
    _ = enums;
}
