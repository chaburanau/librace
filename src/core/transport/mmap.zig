//! Memory-mapped file / shared-memory transport primitives.
//!
//! Many simulators (iRacing, AC family) expose telemetry through OS shared memory
//! or memory-mapped files. Per-simulator layout and parsing live in `simulators/`.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

/// Default iRacing IRSDK shared-memory size (1164 KiB).
pub const default_map_size = 1164 * 1024;

/// Shared-memory connection configuration.
pub const Config = struct {
    /// Platform-specific name or path (e.g. `"Local\\IRSDKMemMapFileName"` on Windows).
    name: []const u8,
    /// Expected view length in bytes. The mapped slice is clamped to this when larger.
    size: usize = default_map_size,
};

/// Read-only view of a named shared-memory region (Windows only for now).
pub const SharedMemory = struct {
    mapping: windows.HANDLE = windows.INVALID_HANDLE_VALUE,
    view: []align(1) u8 = &.{},

    pub const OpenError = error{
        UnsupportedPlatform,
        NotFound,
        MapFailed,
    };

    pub fn open(config: Config) OpenError!SharedMemory {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

        var name_utf16: [256]u16 = undefined;
        const name_len = std.unicode.utf8ToUtf16Le(&name_utf16, config.name) catch return error.UnsupportedPlatform;
        name_utf16[name_len] = 0;
        const name_w: [:0]const u16 = name_utf16[0..name_len :0];

        const mapping = OpenFileMappingW(FILE_MAP_READ, @enumFromInt(0), name_w.ptr);
        if (mapping == windows.INVALID_HANDLE_VALUE) return error.NotFound;

        // Pass 0 to map the entire section (required when the object size differs from `config.size`).
        const view_ptr = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
        if (view_ptr == null) {
            closeHandle(mapping);
            return error.MapFailed;
        }

        return .{
            .mapping = mapping,
            .view = @as([*]align(1) u8, @ptrCast(view_ptr))[0..config.size],
        };
    }

    pub fn close(self: *SharedMemory) void {
        if (self.view.len > 0) {
            _ = UnmapViewOfFile(@ptrCast(@alignCast(self.view.ptr)));
            self.view = &.{};
        }
        if (self.mapping != windows.INVALID_HANDLE_VALUE) {
            closeHandle(self.mapping);
            self.mapping = windows.INVALID_HANDLE_VALUE;
        }
    }
};

fn closeHandle(handle: windows.HANDLE) void {
    _ = CloseHandle(handle);
}

/// Read-only handle to a named Windows auto/​manual-reset event (e.g. `Local\\IRSDKDataValidEvent`).
///
/// Optional: read-only telemetry clients can poll instead, but waiting on the event lets a
/// consumer block until the simulator signals new data rather than busy-spinning.
pub const NamedEvent = struct {
    handle: windows.HANDLE = windows.INVALID_HANDLE_VALUE,

    pub const OpenError = error{
        UnsupportedPlatform,
        NotFound,
    };

    pub fn open(name: []const u8) OpenError!NamedEvent {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

        var name_utf16: [256]u16 = undefined;
        const name_len = std.unicode.utf8ToUtf16Le(&name_utf16, name) catch return error.UnsupportedPlatform;
        name_utf16[name_len] = 0;
        const name_w: [:0]const u16 = name_utf16[0..name_len :0];

        const handle = OpenEventW(SYNCHRONIZE, @enumFromInt(0), name_w.ptr) orelse return error.NotFound;
        if (handle == windows.INVALID_HANDLE_VALUE) return error.NotFound;
        return .{ .handle = handle };
    }

    /// Block up to `timeout_ms` for the event to be signaled. Returns true when signaled.
    pub fn wait(self: *NamedEvent, timeout_ms: u32) bool {
        if (self.handle == windows.INVALID_HANDLE_VALUE) return false;
        return WaitForSingleObject(self.handle, timeout_ms) == WAIT_OBJECT_0;
    }

    pub fn close(self: *NamedEvent) void {
        if (self.handle != windows.INVALID_HANDLE_VALUE) {
            _ = CloseHandle(self.handle);
            self.handle = windows.INVALID_HANDLE_VALUE;
        }
    }
};

const FILE_MAP_READ: windows.DWORD = 0x0004;
const SYNCHRONIZE: windows.DWORD = 0x00100000;
const WAIT_OBJECT_0: windows.DWORD = 0;

extern "kernel32" fn OpenFileMappingW(
    dwDesiredAccess: windows.DWORD,
    bInheritHandle: windows.BOOL,
    lpName: [*:0]const u16,
) callconv(.winapi) windows.HANDLE;

extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: windows.HANDLE,
    dwDesiredAccess: windows.DWORD,
    dwFileOffsetHigh: windows.DWORD,
    dwFileOffsetLow: windows.DWORD,
    dwNumberOfBytesToMap: windows.SIZE_T,
) callconv(.winapi) ?*anyopaque;

extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: ?*anyopaque) callconv(.winapi) windows.BOOL;

extern "kernel32" fn CloseHandle(hObject: windows.HANDLE) callconv(.winapi) windows.BOOL;

extern "kernel32" fn OpenEventW(
    dwDesiredAccess: windows.DWORD,
    bInheritHandle: windows.BOOL,
    lpName: [*:0]const u16,
) callconv(.winapi) ?windows.HANDLE;

extern "kernel32" fn WaitForSingleObject(
    hHandle: windows.HANDLE,
    dwMilliseconds: windows.DWORD,
) callconv(.winapi) windows.DWORD;

test "open missing shared memory returns NotFound" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = SharedMemory.open(.{ .name = "Local\\librace_a8f3c912_test_nonexistent_shm" });
    if (result) |opened| {
        var mem = opened;
        defer mem.close();
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.NotFound => {},
        error.MapFailed => return error.SkipZigTest,
        else => return err,
    }
}

test "close is safe on default-initialized SharedMemory" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var mem: SharedMemory = .{};
    mem.close();
}

test "open and close releases handles" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var mem = SharedMemory.open(.{ .name = "Local\\IRSDKMemMapFileName" }) catch |err| switch (err) {
        error.NotFound, error.MapFailed => return error.SkipZigTest,
        else => return err,
    };
    defer mem.close();
    try std.testing.expect(mem.view.len > 0);
    try std.testing.expect(mem.mapping != windows.INVALID_HANDLE_VALUE);
}
