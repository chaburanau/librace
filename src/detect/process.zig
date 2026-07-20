//! Windows process snapshot and liveness helpers for simulator detection.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const strings = @import("../core/utils/strings.zig");
const signatures = @import("signatures.zig");
const Signature = signatures.Signature;
const Simulator = signatures.Simulator;

pub const Detection = struct {
    simulator: Simulator,
    pid: u32,
};

/// Scan running processes for the first exe basename matching any name in
/// `builtin_sigs`, then `extra_sigs` (case-insensitive exact match).
/// Returns null on non-Windows or when no match is found.
pub fn find(builtin_sigs: []const Signature, extra_sigs: []const Signature) ?Detection {
    if (builtin.os.tag != .windows) return null;
    if (builtin_sigs.len == 0 and extra_sigs.len == 0) return null;

    const snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == windows.INVALID_HANDLE_VALUE) return null;
    defer windows.CloseHandle(snapshot);

    var entry: PROCESSENTRY32W = undefined;
    entry.dwSize = @sizeOf(PROCESSENTRY32W);

    if (Process32FirstW(snapshot, &entry) == @as(windows.BOOL, @enumFromInt(0))) return null;

    var exe_buf: [MAX_PATH * 3]u8 = undefined;
    while (true) {
        const exe_utf8 = strings.utf16ZToUtf8(entry.szExeFile[0..], &exe_buf) orelse {
            if (Process32NextW(snapshot, &entry) == @as(windows.BOOL, @enumFromInt(0))) break;
            continue;
        };

        if (isMatching(exe_utf8, builtin_sigs) orelse isMatching(exe_utf8, extra_sigs)) |sim| {
            return .{
                .simulator = sim,
                .pid = entry.th32ProcessID,
            };
        }

        if (Process32NextW(snapshot, &entry) == @as(windows.BOOL, @enumFromInt(0))) break;
    }

    return null;
}

/// Non-blocking: true if a process with `pid` is still alive.
pub fn isRunning(pid: u32) bool {
    if (builtin.os.tag != .windows) return false;
    if (pid == 0) return false;

    const handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, @enumFromInt(0), pid);
    if (handle == null or handle == windows.INVALID_HANDLE_VALUE) return false;
    defer windows.CloseHandle(handle.?);

    var exit_code: windows.DWORD = 0;
    if (GetExitCodeProcess(handle.?, &exit_code) == @as(windows.BOOL, @enumFromInt(0))) return false;
    return exit_code == STILL_ACTIVE;
}

fn isMatching(exe_basename: []const u8, sigs: []const Signature) ?Simulator {
    for (sigs) |sig| {
        if (std.ascii.eqlIgnoreCase(exe_basename, sig.exe_name)) return sig.simulator;
    }
    return null;
}

const TH32CS_SNAPPROCESS: windows.DWORD = 0x00000002;
const PROCESS_QUERY_LIMITED_INFORMATION: windows.DWORD = 0x1000;
const STILL_ACTIVE: windows.DWORD = 259;
const MAX_PATH = 260;

const PROCESSENTRY32W = extern struct {
    dwSize: windows.DWORD,
    cntUsage: windows.DWORD,
    th32ProcessID: windows.DWORD,
    th32DefaultHeapID: windows.ULONG_PTR,
    th32ModuleID: windows.DWORD,
    cntThreads: windows.DWORD,
    th32ParentProcessID: windows.DWORD,
    pcPriClassBase: windows.LONG,
    dwFlags: windows.DWORD,
    szExeFile: [MAX_PATH]u16,
};

extern "kernel32" fn CreateToolhelp32Snapshot(
    dwFlags: windows.DWORD,
    th32ProcessID: windows.DWORD,
) callconv(.winapi) windows.HANDLE;

extern "kernel32" fn Process32FirstW(
    hSnapshot: windows.HANDLE,
    lppe: *PROCESSENTRY32W,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn Process32NextW(
    hSnapshot: windows.HANDLE,
    lppe: *PROCESSENTRY32W,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn OpenProcess(
    dwDesiredAccess: windows.DWORD,
    bInheritHandle: windows.BOOL,
    dwProcessId: windows.DWORD,
) callconv(.winapi) ?windows.HANDLE;

extern "kernel32" fn GetExitCodeProcess(
    hProcess: windows.HANDLE,
    lpExitCode: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

test "matchFirst is case-insensitive exact match" {
    const sigs = [_]Signature{
        .{ .simulator = .ac, .exe_name = "acs.exe" },
        .{ .simulator = .ams2, .exe_name = "AMS2AVX.exe" },
    };
    try std.testing.expectEqual(Simulator.ac, isMatching("acs.exe", &sigs).?);
    try std.testing.expectEqual(Simulator.ac, isMatching("ACS.EXE", &sigs).?);
    try std.testing.expectEqual(Simulator.ams2, isMatching("ams2avx.exe", &sigs).?);
    try std.testing.expect(isMatching("acs.exe.bak", &sigs) == null);
    try std.testing.expect(isMatching("AMS2.exe", &sigs) == null);
}
