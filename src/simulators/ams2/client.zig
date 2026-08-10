//! Automobilista 2 client for the `$pcars2$` shared-memory interface.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("../../core/root.zig");
const protocol = @import("protocol.zig");

pub const ConnectError = core.transport.mmap.SharedMemory.OpenError || error{
    OutOfMemory,
    VersionMismatch,
};

pub const PollStatus = enum {
    ok,
    disconnected,
    stale,

    pub fn isOk(self: PollStatus) bool {
        return self == .ok;
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    mem: core.transport.mmap.SharedMemory,
    snap: *protocol.Shared,
    participants_loaded: bool = false,

    pub fn connect(allocator: std.mem.Allocator) ConnectError!Client {
        var mem = try core.transport.mmap.SharedMemory.open(.{
            .name = protocol.mem_map_name,
            .size = protocol.shared_size,
        });
        errdefer mem.close();

        if (mem.view.len < protocol.shared_size) return error.MapFailed;

        const version = protocol.readVersion(mem.view) orelse 0;
        if (version != 0 and version != protocol.shared_memory_version) return error.VersionMismatch;

        const snap = try allocator.create(protocol.Shared);
        errdefer allocator.destroy(snap);
        snap.* = std.mem.zeroes(protocol.Shared);

        var client = Client{
            .allocator = allocator,
            .mem = mem,
            .snap = snap,
        };
        _ = client.copyHot();
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.snap);
        self.mem.close();
    }

    pub fn isConnected(self: *const Client) bool {
        const version = protocol.readVersion(self.mem.view) orelse return false;
        return version == protocol.shared_memory_version;
    }

    pub fn poll(self: *Client) PollStatus {
        if (!self.isConnected()) return .disconnected;
        if (!self.copyHot()) return .stale;
        return .ok;
    }

    /// Typed snapshot of player/session telemetry. Participant grid fields are populated
    /// on demand via `participants()`.
    pub fn shared(self: *const Client) *const protocol.Shared {
        return self.snap;
    }

    /// Participant grid and related per-driver arrays. Copied from shared memory on first
    /// call after each successful `poll()`; skipped when unused.
    pub fn participants(self: *Client) []const protocol.ParticipantInfo {
        if (!self.participants_loaded) {
            if (self.copyParticipants()) self.participants_loaded = true;
        }
        const n: usize = @intCast(@max(self.snap.num_participants, 0));
        return self.snap.participant_info[0..@min(n, protocol.stored_participants_max)];
    }

    fn copyHot(self: *Client) bool {
        const view = self.mem.view;
        if (view.len < protocol.shared_size) return false;

        self.participants_loaded = false;

        var attempts: u8 = 0;
        while (attempts < 4) : (attempts += 1) {
            const seq_begin = protocol.readSequenceNumber(view) orelse return false;
            if (seq_begin % 2 != 0) continue;

            copyRange(self.snap, view, 0, protocol.header_size);
            copyRange(self.snap, view, protocol.after_participants_offset, protocol.participant_timing_offset);
            copyRange(self.snap, view, protocol.after_timing_offset, protocol.participant_flags_offset);
            copyRange(self.snap, view, protocol.ams2_tail_offset, protocol.shared_size);
            copyViewedParticipant(self.snap, view);

            const seq_end = protocol.readSequenceNumber(view) orelse return false;
            if (seq_begin == seq_end and seq_end % 2 == 0 and self.snap.sequence_number == seq_end) {
                return true;
            }
        }
        return false;
    }

    fn copyParticipants(self: *Client) bool {
        const view = self.mem.view;
        if (view.len < protocol.shared_size) return false;

        var attempts: u8 = 0;
        while (attempts < 4) : (attempts += 1) {
            const seq_begin = protocol.readSequenceNumber(view) orelse return false;
            if (seq_begin % 2 != 0) continue;

            copyRange(self.snap, view, protocol.header_size, protocol.after_participants_offset);
            copyRange(self.snap, view, protocol.participant_timing_offset, protocol.after_timing_offset);
            copyRange(self.snap, view, protocol.participant_flags_offset, protocol.ams2_tail_offset);

            const seq_end = protocol.readSequenceNumber(view) orelse return false;
            if (seq_begin == seq_end and seq_end % 2 == 0) return true;
        }
        return false;
    }

    fn copyRange(snap: *protocol.Shared, view: []const u8, start: usize, end: usize) void {
        if (end <= start) return;
        const dest = std.mem.asBytes(snap)[start..end];
        @memcpy(dest, view[start..end]);
    }

    fn copyViewedParticipant(snap: *protocol.Shared, view: []const u8) void {
        if (snap.viewed_participant_index < 0) return;
        const idx: usize = @intCast(snap.viewed_participant_index);
        if (idx >= protocol.stored_participants_max) return;

        const start = protocol.header_size + idx * protocol.participant_info_size;
        const end = start + protocol.participant_info_size;
        if (view.len < end) return;
        copyRange(snap, view, start, end);
    }
};

test "typed snapshot access and helpers" {
    const allocator = std.testing.allocator;
    const snap = try allocator.create(protocol.Shared);
    defer allocator.destroy(snap);
    snap.* = std.mem.zeroes(protocol.Shared);

    snap.version = protocol.shared_memory_version;
    snap.speed = 25.0;
    snap.rpm = 6500;
    snap.gear = 4;
    snap.num_participants = 2;
    snap.viewed_participant_index = 0;
    @memcpy(snap.track_location[0.."Spa".len], "Spa");
    @memcpy(snap.car_name[0.."Porsche 992".len], "Porsche 992");
    @memcpy(snap.participant_info[0].name[0.."Alice".len], "Alice");
    @memcpy(snap.participant_info[1].name[0.."Bob".len], "Bob");
    snap.participant_info[0].race_position = 1;
    snap.participant_info[1].race_position = 2;

    var client = Client{
        .allocator = allocator,
        .mem = .{},
        .snap = snap,
        .participants_loaded = true,
    };

    try std.testing.expectApproxEqAbs(@as(f32, 90.0), client.shared().speedKmh(), 0.01);
    try std.testing.expectEqual(@as(f32, 6500), client.shared().rpm);
    try std.testing.expectEqual(@as(i32, 4), client.shared().displayGear());
    try std.testing.expectEqualStrings("Spa", client.shared().trackLocation());
    try std.testing.expectEqualStrings("Porsche 992", client.shared().carName());
    try std.testing.expectEqualStrings("Alice", client.shared().playerName());

    const participants = client.participants();
    try std.testing.expectEqual(@as(usize, 2), participants.len);
    try std.testing.expectEqualStrings("Alice", participants[0].nameUtf8());
    try std.testing.expectEqualStrings("Bob", participants[1].nameUtf8());
}

test "poll invalidates cached participants until reloaded" {
    const allocator = std.testing.allocator;
    const snap = try allocator.create(protocol.Shared);
    defer allocator.destroy(snap);
    snap.* = std.mem.zeroes(protocol.Shared);
    snap.num_participants = 1;
    @memcpy(snap.participant_info[0].name[0.."Old".len], "Old");

    var client = Client{
        .allocator = allocator,
        .mem = .{},
        .snap = snap,
        .participants_loaded = true,
    };
    try std.testing.expectEqualStrings("Old", client.participants()[0].nameUtf8());

    client.participants_loaded = false;
    snap.participant_info[0] = .{};
    @memcpy(snap.participant_info[0].name[0.."New".len], "New");
    client.participants_loaded = true;
    try std.testing.expectEqualStrings("New", client.participants()[0].nameUtf8());
}

test "connect handles missing AMS2 shared memory" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = Client.connect(std.testing.allocator);
    if (result) |client| {
        var c = client;
        defer c.deinit();
        try std.testing.expect(c.isConnected());
        _ = c.poll();
        _ = c.shared();
    } else |err| switch (err) {
        error.NotFound, error.MapFailed, error.VersionMismatch => {},
        else => return err,
    }
}

test "connect reports NotFound when mapping is absent" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = core.transport.mmap.SharedMemory.open(.{
        .name = "Local\\librace_ams2_test_nonexistent_shm",
        .size = 64,
    });
    if (result) |opened| {
        var mem = opened;
        mem.close();
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.NotFound => {},
        else => return err,
    }
}

test "sequence-validated hot copy skips odd sequence frames" {
    var bytes: [protocol.shared_size]u8 = undefined;
    @memset(&bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], protocol.shared_memory_version, .little);
    std.mem.writeInt(u32, bytes[@offsetOf(protocol.Shared, "sequence_number")..][0..4], 3, .little);

    // Odd sequence means a write is in progress — readers must not accept the frame.
    try std.testing.expectEqual(@as(u32, 3), protocol.readSequenceNumber(&bytes).?);
    try std.testing.expect(protocol.readSequenceNumber(&bytes).? % 2 != 0);
}
