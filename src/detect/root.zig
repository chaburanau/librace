//! Process-based simulator detection.
//!
//! Scans running processes for known game executables and reports which title
//! (if any) is running, plus its PID. Use [`isRunning`] to poll whether that
//! PID is still alive. Telemetry readiness is left to each simulator's
//! `connect` timeouts / retries — this module does not probe shared memory or UDP.

const std = @import("std");
const builtin_os = @import("builtin");

const process = @import("process.zig");
const signatures_mod = @import("signatures.zig");

pub const Simulator = signatures_mod.Simulator;
pub const Signature = signatures_mod.Signature;
pub const Detection = process.Detection;

/// Built-in exe basename table.
pub const signatures = signatures_mod.builtin;

/// Detection options. Extra signatures are matched after the built-in table.
pub const Options = struct {
    /// Additional exe names appended after built-in signatures.
    signatures: []const Signature = &.{},
};

/// Which known sim is running (if any), with PID for later [`isRunning`] checks.
pub fn detect(options: Options) ?Detection {
    return process.find(signatures, options.signatures);
}

/// Non-blocking: true if the process with this PID is still alive.
pub fn isRunning(pid: u32) bool {
    return process.isRunning(pid);
}

test "builtin signatures cover every Simulator" {
    var seen = std.EnumSet(Simulator).initEmpty();
    for (signatures) |sig| {
        seen.insert(sig.simulator);
    }
    inline for (@typeInfo(Simulator).@"enum".fields) |field| {
        const sim: Simulator = @enumFromInt(field.value);
        try std.testing.expect(seen.contains(sim));
    }
}

test "isRunning rejects pid 0" {
    try std.testing.expect(!isRunning(0));
}

test "isRunning current process on Windows" {
    if (builtin_os.os.tag != .windows) return error.SkipZigTest;
    const pid: u32 = @intCast(std.os.windows.GetCurrentProcessId());
    try std.testing.expect(isRunning(pid));
}

test "detect does not panic" {
    // May or may not find a sim; just ensure the scan completes.
    _ = detect(.{});
}
