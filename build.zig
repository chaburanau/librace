const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("librace", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const example_common = b.addModule("example_common", .{
        .root_source_file = b.path("examples/common/root.zig"),
        .target = target,
    });

    const simulators = [_][]const u8{
        "iracing",
        "ac",
        "acc",
        "ace",
        "acr",
        "fh6",
        "lmu",
    };

    for (simulators) |sim| {
        addSimpleExample(b, mod, example_common, target, optimize, sim);
    }

    var dashboard_run_cmds: [simulators.len]*std.Build.Step.Run = undefined;
    for (simulators, 0..) |sim, i| {
        dashboard_run_cmds[i] = addDashboardForSim(b, mod, example_common, target, optimize, sim);
    }

    const dashboard_sim = b.option([]const u8, "sim", "Simulator for the legacy `dashboard` step (prefer `run-dashboard-<sim>`)") orelse "iracing";
    var dashboard_sim_valid = false;
    var dashboard_sim_index: usize = 0;
    for (simulators, 0..) |name, i| {
        if (std.mem.eql(u8, dashboard_sim, name)) {
            dashboard_sim_valid = true;
            dashboard_sim_index = i;
            break;
        }
    }
    if (!dashboard_sim_valid) {
        std.debug.panic("unknown simulator '{s}' — expected one of: iracing, ac, acc, ace, acr, fh6, lmu", .{dashboard_sim});
    }

    const dashboard_step = b.step(
        "dashboard",
        b.fmt("Run dashboard for sim={s} (same as run-dashboard-{s})", .{ dashboard_sim, dashboard_sim }),
    );
    dashboard_step.dependOn(&dashboard_run_cmds[dashboard_sim_index].step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn addSimpleExample(
    b: *std.Build,
    mod: *std.Build.Module,
    example_common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sim: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = sim,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}/simple.zig", .{sim})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "librace", .module = mod },
                .{ .name = "example_common", .module = example_common },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step(
        b.fmt("run-{s}", .{sim}),
        b.fmt("Run the {s} simple smoke-test example", .{sim}),
    );
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn addDashboardForSim(
    b: *std.Build,
    mod: *std.Build.Module,
    example_common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sim: []const u8,
) *std.Build.Step.Run {
    const is_iracing = std.mem.eql(u8, sim, "iracing");
    const is_ac = std.mem.eql(u8, sim, "ac");
    const is_acc = std.mem.eql(u8, sim, "acc");
    const is_ace = std.mem.eql(u8, sim, "ace");
    const is_acr = std.mem.eql(u8, sim, "acr");
    const is_fh6 = std.mem.eql(u8, sim, "fh6");
    const is_lmu = std.mem.eql(u8, sim, "lmu");
    const implemented = is_iracing or is_ac or is_acc or is_ace or is_acr or is_fh6 or is_lmu;

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "short_name", sim);
    build_options.addOption([]const u8, "simulator_name", simulatorDisplayName(sim));
    build_options.addOption(bool, "implemented", implemented);

    const exe = if (implemented) blk: {
        const sim_module = b.addModule(b.fmt("sim_{s}", .{sim}), .{
            .root_source_file = b.path(b.fmt("examples/{s}/dashboard.zig", .{sim})),
            .target = target,
            .imports = &.{
                .{ .name = "librace", .module = mod },
                .{ .name = "example_common", .module = example_common },
            },
        });

        if (is_iracing) {
            const iracing_connect = b.addModule("iracing_connect", .{
                .root_source_file = b.path("examples/iracing/connect_error.zig"),
                .target = target,
            });
            sim_module.addImport("iracing_connect", iracing_connect);
        }

        break :blk b.addExecutable(.{
            .name = b.fmt("dashboard-{s}", .{sim}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/common/dashboard_main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "librace", .module = mod },
                    .{ .name = "example_common", .module = example_common },
                    .{ .name = "build_options", .module = build_options.createModule() },
                    .{ .name = "sim", .module = sim_module },
                },
            }),
        });
    } else blk: {
        break :blk b.addExecutable(.{
            .name = b.fmt("dashboard-{s}", .{sim}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/common/dashboard_main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "librace", .module = mod },
                    .{ .name = "example_common", .module = example_common },
                    .{ .name = "build_options", .module = build_options.createModule() },
                },
            }),
        });
    };
    b.installArtifact(exe);

    const run_step = b.step(
        b.fmt("run-dashboard-{s}", .{sim}),
        b.fmt("Run the {s} dashboard", .{simulatorDisplayName(sim)}),
    );
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    return run_cmd;
}

fn simulatorDisplayName(short_name: []const u8) []const u8 {
    if (std.mem.eql(u8, short_name, "iracing")) return "iRacing";
    if (std.mem.eql(u8, short_name, "ac")) return "Assetto Corsa";
    if (std.mem.eql(u8, short_name, "acc")) return "Assetto Corsa Competizione";
    if (std.mem.eql(u8, short_name, "ace")) return "Assetto Corsa Evo";
    if (std.mem.eql(u8, short_name, "acr")) return "Assetto Corsa Rally";
    if (std.mem.eql(u8, short_name, "fh6")) return "Forza Horizon 6";
    if (std.mem.eql(u8, short_name, "lmu")) return "Le Mans Ultimate";
    return short_name;
}
