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
        "lmu",
    };

    for (simulators) |sim| {
        addSimpleExample(b, mod, example_common, target, optimize, sim);
    }

    addDashboardExample(b, mod, example_common, target, optimize, &simulators);

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

fn addDashboardExample(
    b: *std.Build,
    mod: *std.Build.Module,
    example_common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    simulators: []const []const u8,
) void {
    const sim = b.option([]const u8, "sim", "Simulator short name for the dashboard example") orelse "iracing";

    var sim_valid = false;
    for (simulators) |name| {
        if (std.mem.eql(u8, sim, name)) {
            sim_valid = true;
            break;
        }
    }
    if (!sim_valid) {
        std.debug.panic("unknown simulator '{s}' — expected one of: iracing, ac, acc, ace, acr, lmu", .{sim});
    }

    const is_iracing = std.mem.eql(u8, sim, "iracing");
    const is_ac = std.mem.eql(u8, sim, "ac");
    const is_ace = std.mem.eql(u8, sim, "ace");
    const is_acr = std.mem.eql(u8, sim, "acr");
    const implemented = is_iracing or is_ac or is_ace or is_acr;

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "short_name", sim);
    build_options.addOption([]const u8, "simulator_name", simulatorDisplayName(sim));
    build_options.addOption(bool, "implemented", implemented);

    const exe = if (implemented) blk: {
        const sim_module = b.addModule("sim", .{
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
            .name = "dashboard",
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
            .name = "dashboard",
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
        "dashboard",
        b.fmt("Run the shared dashboard example (sim={s})", .{sim}),
    );
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn simulatorDisplayName(short_name: []const u8) []const u8 {
    if (std.mem.eql(u8, short_name, "iracing")) return "iRacing";
    if (std.mem.eql(u8, short_name, "ac")) return "Assetto Corsa";
    if (std.mem.eql(u8, short_name, "acc")) return "Assetto Corsa Competizione";
    if (std.mem.eql(u8, short_name, "ace")) return "Assetto Corsa Evo";
    if (std.mem.eql(u8, short_name, "acr")) return "Assetto Corsa Rally";
    if (std.mem.eql(u8, short_name, "lmu")) return "Le Mans Ultimate";
    return short_name;
}
