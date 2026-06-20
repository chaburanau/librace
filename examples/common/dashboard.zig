//! Terminal dashboard runner shared by all simulator examples.
//!
//! Each simulator provider fills a common [`Data`] snapshot; this module renders it.

const std = @import("std");

pub const max_sections = 8;
pub const max_rows_per_section = 16;
pub const max_stats = 64;
pub const value_buf_len = 64;

pub const Config = struct {
    title: []const u8,
    refresh_ms: u32 = 100,
    /// Stop after N redraws (`null` = run until disconnected).
    max_frames: ?u32 = null,
    /// Sections per horizontal band in the layout.
    columns: usize = 3,
};

/// Normalized dashboard snapshot — same shape for every simulator provider.
pub const Data = struct {
    header_left: []const u8 = "",
    header_right: []const u8 = "",

    track: []const u8 = "?",
    car: []const u8 = "?",
    driver: []const u8 = "?",
    session_type: []const u8 = "?",
    track_length: []const u8 = "?",
    on_track: []const u8 = "?",

    speed_kmh: f64 = 0,
    gear: f64 = 0,
    rpm: f64 = 0,
    lap: f64 = 0,
    lap_cur: f64 = 0,
    lap_best: f64 = 0,
    lap_last: f64 = 0,
    fuel: f64 = 0,
    fuel_h: f64 = 0,

    throttle_pct: f64 = 0,
    brake_pct: f64 = 0,
    clutch_pct: f64 = 0,
    steering_deg: f64 = 0,

    lat_g: f64 = 0,
    long_g: f64 = 0,
    vert_g: f64 = 0,
    yaw: f64 = 0,
    pitch: f64 = 0,
    roll: f64 = 0,

    session_state: f64 = 0,
    session_time: f64 = 0,
    session_num: f64 = 0,

    var_count: usize = 0,
    discovery_hint: []const u8 = "?",
};

const Stat = enum(usize) {
    speed,
    gear,
    rpm,
    lap,
    lap_cur,
    lap_best,
    lap_last,
    fuel,
    fuel_h,
    throttle,
    brake,
    clutch,
    steering,
    lat_g,
    long_g,
    vert_g,
    yaw,
    pitch,
    roll,
    sess_state,
    sess_time,
    sess_num,
};

pub const StatEntry = struct {
    active: bool = false,
    cur: f64 = 0,
    min: f64 = 0,
    max: f64 = 0,

    pub fn observe(self: *StatEntry, value: f64) void {
        self.cur = value;
        if (!self.active) {
            self.min = value;
            self.max = value;
            self.active = true;
        } else {
            self.min = @min(self.min, value);
            self.max = @max(self.max, value);
        }
    }
};

pub const Stats = struct {
    entries: [max_stats]StatEntry = [_]StatEntry{.{}} ** max_stats,

    pub fn reset(self: *Stats) void {
        self.* = .{};
    }

    pub fn update(self: *Stats, id: usize, value: f64) void {
        if (id >= max_stats) return;
        self.entries[id].observe(value);
    }

    pub fn get(self: *const Stats, id: usize) *const StatEntry {
        return &self.entries[@min(id, max_stats - 1)];
    }
};

pub const Row = struct {
    label: [20]u8 = undefined,
    label_len: usize = 0,
    value: [value_buf_len]u8 = undefined,
    value_len: usize = 0,
    is_stat: bool = false,

    pub fn setLabel(self: *Row, text: []const u8) void {
        const len = @min(text.len, self.label.len);
        @memcpy(self.label[0..len], text[0..len]);
        self.label_len = len;
    }

    pub fn labelSlice(self: *const Row) []const u8 {
        return self.label[0..self.label_len];
    }

    pub fn set(self: *Row, text: []const u8) void {
        self.is_stat = false;
        const len = @min(text.len, value_buf_len);
        @memcpy(self.value[0..len], text[0..len]);
        self.value_len = len;
    }

    pub fn fmt(self: *Row, comptime fmt_str: []const u8, args: anytype) void {
        self.is_stat = false;
        const written = std.fmt.bufPrint(self.value[0..], fmt_str, args) catch {
            self.set("<?>");
            return;
        };
        self.value_len = written.len;
    }

    pub fn fmtStat(self: *Row, entry: *const StatEntry, comptime decimals: u32, suffix: []const u8) void {
        self.is_stat = true;
        if (!entry.active) {
            self.set("—");
            return;
        }
        const written = switch (decimals) {
            0 => std.fmt.bufPrint(self.value[0..], "{d:.0} {d:.0} {d:.0}{s}", .{
                entry.cur, entry.min, entry.max, suffix,
            }),
            1 => std.fmt.bufPrint(self.value[0..], "{d:.1} {d:.1} {d:.1}{s}", .{
                entry.cur, entry.min, entry.max, suffix,
            }),
            2 => std.fmt.bufPrint(self.value[0..], "{d:.2} {d:.2} {d:.2}{s}", .{
                entry.cur, entry.min, entry.max, suffix,
            }),
            3 => std.fmt.bufPrint(self.value[0..], "{d:.3} {d:.3} {d:.3}{s}", .{
                entry.cur, entry.min, entry.max, suffix,
            }),
            else => std.fmt.bufPrint(self.value[0..], "{d:.0} {d:.0} {d:.0}{s}", .{
                entry.cur, entry.min, entry.max, suffix,
            }),
        } catch {
            self.set("<?>");
            return;
        };
        self.value_len = written.len;
    }

    pub fn valueSlice(self: *const Row) []const u8 {
        return self.value[0..self.value_len];
    }
};

pub const Section = struct {
    title: [24]u8 = undefined,
    title_len: usize = 0,
    rows: [max_rows_per_section]Row = undefined,
    row_count: usize = 0,
    has_stats: bool = false,

    pub fn init(title: []const u8) Section {
        var section: Section = .{};
        section.setTitle(title);
        return section;
    }

    pub fn setTitle(self: *Section, title: []const u8) void {
        const len = @min(title.len, self.title.len);
        @memcpy(self.title[0..len], title[0..len]);
        self.title_len = len;
    }

    pub fn titleSlice(self: *const Section) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn addRow(self: *Section, label: []const u8) *Row {
        std.debug.assert(self.row_count < max_rows_per_section);
        const row = &self.rows[self.row_count];
        row.* = .{};
        row.setLabel(label);
        self.row_count += 1;
        return row;
    }

    pub fn addStatRow(self: *Section, label: []const u8, entry: *const StatEntry, comptime decimals: u32, suffix: []const u8) void {
        self.has_stats = true;
        self.addRow(label).fmtStat(entry, decimals, suffix);
    }
};

pub const Frame = struct {
    header_left: [48]u8 = undefined,
    header_left_len: usize = 0,
    header_right: [48]u8 = undefined,
    header_right_len: usize = 0,
    sections: [max_sections]Section = undefined,
    section_count: usize = 0,

    pub fn setHeader(self: *Frame, left: []const u8, right: []const u8) void {
        self.header_left_len = @min(left.len, self.header_left.len);
        @memcpy(self.header_left[0..self.header_left_len], left[0..self.header_left_len]);
        self.header_right_len = @min(right.len, self.header_right.len);
        @memcpy(self.header_right[0..self.header_right_len], right[0..self.header_right_len]);
    }

    pub fn addSection(self: *Frame, title: []const u8) *Section {
        std.debug.assert(self.section_count < max_sections);
        const section = &self.sections[self.section_count];
        section.* = Section.init(title);
        self.section_count += 1;
        return section;
    }
};

pub fn defaultConnectErrorHint(_: anytype, err: anyerror, w: *std.Io.Writer) !void {
    try w.print("Connect failed: {s}\n", .{@errorName(err)});
}

fn updateStats(stats: *Stats, data: *const Data) void {
    stats.update(@intFromEnum(Stat.speed), data.speed_kmh);
    stats.update(@intFromEnum(Stat.gear), data.gear);
    stats.update(@intFromEnum(Stat.rpm), data.rpm);
    stats.update(@intFromEnum(Stat.lap), data.lap);
    stats.update(@intFromEnum(Stat.lap_cur), data.lap_cur);
    stats.update(@intFromEnum(Stat.lap_best), data.lap_best);
    stats.update(@intFromEnum(Stat.lap_last), data.lap_last);
    stats.update(@intFromEnum(Stat.fuel), data.fuel);
    stats.update(@intFromEnum(Stat.fuel_h), data.fuel_h);
    stats.update(@intFromEnum(Stat.throttle), data.throttle_pct);
    stats.update(@intFromEnum(Stat.brake), data.brake_pct);
    stats.update(@intFromEnum(Stat.clutch), data.clutch_pct);
    stats.update(@intFromEnum(Stat.steering), data.steering_deg);
    stats.update(@intFromEnum(Stat.lat_g), data.lat_g);
    stats.update(@intFromEnum(Stat.long_g), data.long_g);
    stats.update(@intFromEnum(Stat.vert_g), data.vert_g);
    stats.update(@intFromEnum(Stat.yaw), data.yaw);
    stats.update(@intFromEnum(Stat.pitch), data.pitch);
    stats.update(@intFromEnum(Stat.roll), data.roll);
    stats.update(@intFromEnum(Stat.sess_state), data.session_state);
    stats.update(@intFromEnum(Stat.sess_time), data.session_time);
    stats.update(@intFromEnum(Stat.sess_num), data.session_num);
}

pub fn renderData(data: *const Data, stats: *const Stats, frame: *Frame) void {
    frame.setHeader(data.header_left, data.header_right);

    const session = frame.addSection("Session");
    session.addRow("Track").set(data.track);
    session.addRow("Car").set(data.car);
    session.addRow("Driver").set(data.driver);
    session.addRow("Type").set(data.session_type);
    session.addRow("Len").set(data.track_length);
    session.addRow("OnTrk").set(data.on_track);

    const drive = frame.addSection("Drive");
    drive.addStatRow("Spd", stats.get(@intFromEnum(Stat.speed)), 0, "k");
    drive.addStatRow("Gear", stats.get(@intFromEnum(Stat.gear)), 0, "");
    drive.addStatRow("RPM", stats.get(@intFromEnum(Stat.rpm)), 0, "");
    drive.addStatRow("Lap", stats.get(@intFromEnum(Stat.lap)), 0, "");
    drive.addStatRow("Cur", stats.get(@intFromEnum(Stat.lap_cur)), 3, "s");
    drive.addStatRow("Best", stats.get(@intFromEnum(Stat.lap_best)), 3, "s");
    drive.addStatRow("Last", stats.get(@intFromEnum(Stat.lap_last)), 3, "s");
    drive.addStatRow("Fuel", stats.get(@intFromEnum(Stat.fuel)), 1, "L");
    drive.addStatRow("F/h", stats.get(@intFromEnum(Stat.fuel_h)), 1, "");

    const inputs = frame.addSection("Input");
    inputs.addStatRow("Thr", stats.get(@intFromEnum(Stat.throttle)), 0, "%");
    inputs.addStatRow("Brk", stats.get(@intFromEnum(Stat.brake)), 0, "%");
    inputs.addStatRow("Clt", stats.get(@intFromEnum(Stat.clutch)), 0, "%");
    inputs.addStatRow("Str", stats.get(@intFromEnum(Stat.steering)), 1, "°");

    const motion = frame.addSection("Motion");
    motion.addStatRow("Lat", stats.get(@intFromEnum(Stat.lat_g)), 2, "G");
    motion.addStatRow("Long", stats.get(@intFromEnum(Stat.long_g)), 2, "G");
    motion.addStatRow("Vert", stats.get(@intFromEnum(Stat.vert_g)), 2, "G");
    motion.addStatRow("Yaw", stats.get(@intFromEnum(Stat.yaw)), 1, "°");
    motion.addStatRow("Pitch", stats.get(@intFromEnum(Stat.pitch)), 1, "°");
    motion.addStatRow("Roll", stats.get(@intFromEnum(Stat.roll)), 1, "°");

    const timing = frame.addSection("Timing");
    timing.addStatRow("State", stats.get(@intFromEnum(Stat.sess_state)), 0, "");
    timing.addStatRow("Time", stats.get(@intFromEnum(Stat.sess_time)), 1, "s");
    timing.addStatRow("Sess#", stats.get(@intFromEnum(Stat.sess_num)), 0, "");

    const discovery = frame.addSection("Discovery");
    discovery.addRow("Catalog").set(data.discovery_hint);
}

/// Unimplemented simulators: print `FAIL not_implemented` and exit immediately.
pub fn failNotImplemented(io: std.Io, short_name: []const u8) !void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.print("FAIL not_implemented short_name={s}\n", .{short_name});
    try stdout.flush();
    return error.ExampleFailed;
}

pub fn run(
    io: std.Io,
    cfg: Config,
    ctx: anytype,
    comptime Provider: type,
) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    Provider.connect(ctx) catch |err| {
        try Provider.connectErrorHint(ctx, err, stderr);
        try stderr.flush();
        return err;
    };
    defer Provider.deinit(ctx);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    enterAltScreen(stdout);
    defer leaveAltScreen(stdout);

    var stats: Stats = .{};
    var frame: Frame = .{};
    var frames: u32 = 0;

    while (true) {
        if (!Provider.isConnected(ctx)) {
            try clearScreen(stdout);
            try stdout.print("Disconnected.\n", .{});
            try stdout.flush();
            break;
        }

        _ = Provider.poll(ctx);

        var data: Data = .{};
        Provider.fillData(ctx, &data);
        updateStats(&stats, &data);

        frame = .{};
        renderData(&data, &stats, &frame);
        try draw(stdout, cfg, &frame);
        try stdout.flush();

        frames += 1;
        if (cfg.max_frames) |max| {
            if (frames >= max) break;
        }

        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(cfg.refresh_ms), .real);
    }
}

fn enterAltScreen(stdout: *std.Io.Writer) void {
    _ = stdout.print("\x1b[?1049h", .{}) catch {};
    _ = stdout.print("\x1b[?25l", .{}) catch {};
}

fn leaveAltScreen(stdout: *std.Io.Writer) void {
    _ = stdout.print("\x1b[?25h", .{}) catch {};
    _ = stdout.print("\x1b[?1049l", .{}) catch {};
}

fn clearScreen(stdout: *std.Io.Writer) !void {
    try stdout.print("\x1b[H\x1b[2J\x1b[3J", .{});
}

const col_width: usize = 38;

fn draw(stdout: *std.Io.Writer, cfg: Config, frame: *const Frame) !void {
    try clearScreen(stdout);

    try stdout.print("{s}", .{cfg.title});
    if (frame.header_right_len > 0) {
        try stdout.print(" | {s}", .{frame.header_right[0..frame.header_right_len]});
    }
    if (frame.header_left_len > 0) {
        try stdout.print(" | {s}", .{frame.header_left[0..frame.header_left_len]});
    }
    try stdout.print("\n", .{});

    const columns = @max(cfg.columns, 1);
    var si: usize = 0;
    while (si < frame.section_count) {
        const end = @min(si + columns, frame.section_count);

        for (si..end) |i| {
            try writePadded(stdout, frame.sections[i].titleSlice(), col_width, '[', ']');
        }
        try stdout.print("\n", .{});

        var has_stats = false;
        for (si..end) |i| {
            if (frame.sections[i].has_stats) has_stats = true;
        }
        if (has_stats) {
            for (si..end) |i| {
                if (frame.sections[i].has_stats) {
                    try writeStatHeader(stdout, col_width);
                } else {
                    try writeSpaces(stdout, col_width);
                }
            }
            try stdout.print("\n", .{});
        }

        var max_rows: usize = 0;
        for (si..end) |i| {
            max_rows = @max(max_rows, frame.sections[i].row_count);
        }

        var ri: usize = 0;
        while (ri < max_rows) : (ri += 1) {
            for (si..end) |i| {
                const sec = &frame.sections[i];
                if (ri < sec.row_count) {
                    try writeRow(stdout, &sec.rows[ri], col_width);
                } else {
                    try writeSpaces(stdout, col_width);
                }
            }
            try stdout.print("\n", .{});
        }

        si = end;
    }

    try stdout.print("Ctrl+C quit\n", .{});
}

fn writeStatHeader(stdout: *std.Io.Writer, width: usize) !void {
    var buf: [col_width]u8 = undefined;
    const written = std.fmt.bufPrint(buf[0..width], "{s:<9}{s:>8}{s:>8}{s:>8}", .{ "", "cur", "min", "max" }) catch return;
    try stdout.print("{s}", .{written});
    if (written.len < width) try writeSpaces(stdout, width - written.len);
}

fn writeRow(stdout: *std.Io.Writer, row: *const Row, width: usize) !void {
    var buf: [col_width]u8 = undefined;
    const written = if (row.is_stat) blk: {
        break :blk std.fmt.bufPrint(
            buf[0..width],
            "{s:<9}{s}",
            .{ row.labelSlice(), row.valueSlice() },
        ) catch return;
    } else blk: {
        break :blk std.fmt.bufPrint(
            buf[0..width],
            "{s:<9} {s}",
            .{ row.labelSlice(), row.valueSlice() },
        ) catch return;
    };
    if (written.len < width) {
        try stdout.print("{s}", .{written});
        try writeSpaces(stdout, width - written.len);
    } else {
        try stdout.print("{s}", .{written[0..width]});
    }
}

fn writePadded(stdout: *std.Io.Writer, text: []const u8, width: usize, l: u8, r: u8) !void {
    var inner: [40]u8 = undefined;
    const inner_len = @min(text.len, inner.len);
    @memcpy(inner[0..inner_len], text[0..inner_len]);
    const total = inner_len + 2;
    if (total >= width) {
        try stdout.print("{c}{s}{c}", .{ l, inner[0..@min(inner.len, width - 2)], r });
        return;
    }
    try stdout.print("{c}{s}{c}", .{ l, inner[0..inner_len], r });
    try writeSpaces(stdout, width - total);
}

fn writeSpaces(stdout: *std.Io.Writer, count: usize) !void {
    var remaining = count;
    const chunk = "                                        ";
    while (remaining > 0) {
        const n = @min(remaining, chunk.len);
        try stdout.print("{s}", .{chunk[0..n]});
        remaining -= n;
    }
}
