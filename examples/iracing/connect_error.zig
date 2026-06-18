//! Connect-error hints for iRacing / IRSDK-style shared memory.

const std = @import("std");

pub fn printConnectError(_: anytype, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
    switch (err) {
        error.NotFound => try w.print("Shared memory not found — is the simulator running?\n", .{}),
        error.MapFailed => try w.print("Shared memory found but could not be mapped.\n", .{}),
        error.InvalidHeader => try w.print("Shared memory mapped but protocol header is invalid.\n", .{}),
        error.UnsupportedPlatform => try w.print("This simulator telemetry is only supported on Windows.\n", .{}),
        else => try w.print("Enter a live session before running the example.\n", .{}),
    }
}
