//! Minimal smoke-test runner for simulator examples.
//!
//! Prints machine-readable `OK` / `FAIL` lines suitable for manual checks.

const std = @import("std");

pub const Config = struct {
    simulator_name: []const u8,
    transport: []const u8,
    short_name: []const u8,
    /// Number of poll iterations before exiting successfully.
    sample_count: u32 = 5,
    poll_interval_ms: u32 = 100,
};

pub const Outcome = enum {
    ok,
    not_implemented,
    connect_failed,
    not_connected,
    poll_failed,
};

pub const Result = struct {
    outcome: Outcome,
    connect_error: ?[]const u8 = null,
    track: []const u8 = "",
    car: []const u8 = "",
    gear: i32 = 0,
    speed_kmh: f32 = 0,
    rpm: f32 = 0,
    var_count: usize = 0,
};

pub const Sample = struct {
    track: []const u8 = "?",
    car: []const u8 = "?",
    gear: i32 = 0,
    speed_kmh: f32 = 0,
    rpm: f32 = 0,
};

pub fn defaultConnectErrorHint(
    _: anytype,
    err: anyerror,
    w: *std.Io.Writer,
) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
}

/// Unimplemented simulators: print `FAIL not_implemented` and return immediately.
pub fn failNotImplemented(io: std.Io, short_name: []const u8) !Result {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.print("FAIL not_implemented short_name={s}\n", .{short_name});
    try stdout.flush();
    return .{ .outcome = .not_implemented };
}

/// Exit with status 0 on success, 1 on any failure outcome.
pub fn finish(result: Result) !void {
    switch (result.outcome) {
        .ok => return,
        else => return error.ExampleFailed,
    }
}

pub fn run(
    io: std.Io,
    cfg: Config,
    ctx: anytype,
    comptime Hooks: type,
) !Result {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.print("librace simple example: {s}\n", .{cfg.simulator_name});
    try stdout.print("Transport: {s}\n", .{cfg.transport});
    try stdout.flush();

    Hooks.connect(ctx, io) catch |err| {
        if (err == error.NotImplemented) {
            try stdout.print("FAIL not_implemented short_name={s}\n", .{cfg.short_name});
            try stdout.flush();
            return .{ .outcome = .not_implemented };
        }
        try Hooks.connectErrorHint(ctx, err, stdout);
        try stdout.flush();
        return .{
            .outcome = .connect_failed,
            .connect_error = @errorName(err),
        };
    };
    defer Hooks.deinit(ctx);

    if (!Hooks.isConnected(ctx)) {
        try stdout.print("FAIL not_connected\n", .{});
        try stdout.flush();
        return .{ .outcome = .not_connected };
    }

    const var_count = Hooks.varCount(ctx);
    var last: Sample = .{};
    var got_sample = false;
    var i: u32 = 0;
    while (i < cfg.sample_count) : (i += 1) {
        if (!Hooks.poll(ctx)) {
            try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(cfg.poll_interval_ms), .real);
            continue;
        }
        var sample: Sample = .{};
        Hooks.readSample(ctx, &sample);
        last = sample;
        got_sample = true;
        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(cfg.poll_interval_ms), .real);
    }

    if (!got_sample) {
        try stdout.print("FAIL poll_failed vars={d}\n", .{var_count});
        try stdout.flush();
        return .{ .outcome = .poll_failed, .var_count = var_count };
    }

    try stdout.print(
        "OK track={s} car={s} gear={d} speed_kmh={d:.1} rpm={d:.0} vars={d}\n",
        .{ last.track, last.car, last.gear, last.speed_kmh, last.rpm, var_count },
    );
    try stdout.flush();

    return .{
        .outcome = .ok,
        .track = last.track,
        .car = last.car,
        .gear = last.gear,
        .speed_kmh = last.speed_kmh,
        .rpm = last.rpm,
        .var_count = var_count,
    };
}
