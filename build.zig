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

    const examples = [_]struct { name: []const u8, root: []const u8 }{
        .{ .name = "iracing", .root = "examples/iracing/main.zig" },
        .{ .name = "ac", .root = "examples/ac/main.zig" },
        .{ .name = "acc", .root = "examples/acc/main.zig" },
        .{ .name = "ace", .root = "examples/ace/main.zig" },
        .{ .name = "acr", .root = "examples/acr/main.zig" },
        .{ .name = "lmu", .root = "examples/lmu/main.zig" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.root),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "librace", .module = mod },
                },
            }),
        });
        b.installArtifact(exe);

        const run_step = b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run the {s} telemetry example", .{example.name}),
        );
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);
}
