const std = @import("std");
const librace = @import("librace");
const example_common = @import("example_common");

const ir = librace.simulators.iracing;
const simple = example_common.simple;
const connect_error = @import("connect_error.zig");

const Indices = struct {
    gear: ?ir.Variable = null,
    speed: ?ir.Variable = null,
    rpm: ?ir.Variable = null,
};

const Context = struct {
    client: ?ir.Client = null,
    session_snapshot: ?ir.SessionSnapshot = null,
    indices: Indices = .{},
    variables_version: u64 = 0,
    track_buf: [128]u8 = undefined,
    car_buf: [128]u8 = undefined,

    pub fn connect(ctx: *Context, io: std.Io) !void {
        ctx.client = try ir.connect(std.heap.page_allocator, io, .{});
    }

    pub fn deinit(ctx: *Context, _: std.Io) void {
        if (ctx.session_snapshot) |*snapshot| snapshot.deinit();
        if (ctx.client) |*client| client.deinit();
        ctx.* = .{};
    }

    pub fn isConnected(ctx: *Context) bool {
        return ctx.client.?.isConnected();
    }

    pub fn poll(ctx: *Context, _: std.Io) bool {
        if (!ctx.client.?.waitAndPoll(std.Io.Duration.fromMilliseconds(20)).isOk()) return false;
        ctx.refreshSnapshots() catch return false;
        return true;
    }

    pub fn varCount(ctx: *Context) usize {
        return ctx.client.?.header().variablesLen();
    }

    pub fn readSample(ctx: *Context, sample: *simple.Sample) void {
        const variables = ctx.client.?.variables();
        const session = if (ctx.session_snapshot) |*snapshot| snapshot else return;

        sample.track = sessionString(session, ir.keys.session.weekend_info, ir.keys.session.track_display_name, &ctx.track_buf) orelse
            sessionString(session, ir.keys.session.weekend_info, ir.keys.session.track_name, &ctx.track_buf) orelse "?";
        sample.car = playerDriverString(session, ir.keys.driver.car_screen_name, &ctx.car_buf) orelse
            playerDriverString(session, ir.keys.driver.car_path, &ctx.car_buf) orelse "?";
        sample.gear = readInt(variables, ctx.indices.gear) orelse 0;
        sample.speed_kmh = (readFloat(variables, ctx.indices.speed) orelse 0) * 3.6;
        sample.rpm = readFloat(variables, ctx.indices.rpm) orelse 0;
    }

    fn refreshSnapshots(ctx: *Context) !void {
        const client = &ctx.client.?;
        const variables = client.variables();
        if (ctx.variables_version != variables.version()) {
            ctx.indices = .{
                .gear = try variables.find(ir.keys.var_name.gear),
                .speed = try variables.find(ir.keys.var_name.speed),
                .rpm = try variables.find(ir.keys.var_name.rpm),
            };
            ctx.variables_version = variables.version();
        }

        const session_version = client.session().version() orelse return;
        if (ctx.session_snapshot == null or ctx.session_snapshot.?.version != session_version) {
            var replacement = try client.session().snapshot();
            errdefer replacement.deinit();
            if (ctx.session_snapshot) |*snapshot| snapshot.deinit();
            ctx.session_snapshot = replacement;
        }
    }

    pub fn connectErrorHint(ctx: *Context, err: anyerror, writer: *std.Io.Writer) !void {
        try connect_error.printConnectError(ctx, err, writer);
    }
};

fn readInt(variables: ir.VariablesView, index: ?ir.Variable) ?i32 {
    const value = variables.value(index orelse return null) catch return null;
    return value.asInt();
}

fn readFloat(variables: ir.VariablesView, index: ?ir.Variable) ?f32 {
    const value = variables.value(index orelse return null) catch return null;
    return @floatCast(value.asFloat() orelse return null);
}

fn sessionString(
    snapshot: *const ir.SessionSnapshot,
    section: []const u8,
    key: []const u8,
    buffer: []u8,
) ?[]const u8 {
    const scalar = (snapshot.query(&.{
        .{ .key = section },
        .{ .key = key },
    }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}

fn playerDriverString(snapshot: *const ir.SessionSnapshot, key: []const u8, buffer: []u8) ?[]const u8 {
    const player = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.driver_car_idx },
    }) catch return null) orelse return null;
    const player_index = player.asInt() catch return null;
    const scalar = (snapshot.query(&.{
        .{ .key = ir.keys.session.driver_info },
        .{ .key = ir.keys.session.drivers },
        .{ .select = .{
            .key = ir.keys.driver.car_idx,
            .value = .{ .int = player_index },
        } },
        .{ .key = key },
    }) catch return null) orelse return null;
    return scalar.string(buffer) catch null;
}

pub fn main(init: std.process.Init) !void {
    var ctx: Context = .{};
    const result = try simple.run(init.io, .{
        .simulator_name = ir.name,
        .transport = @tagName(ir.transport),
        .short_name = "iracing",
    }, &ctx, Context);
    try simple.finish(result);
}
