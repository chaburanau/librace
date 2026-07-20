const std = @import("std");
const librace = @import("librace");

pub fn main(init: std.process.Init) !void {
    var manager = librace.unified.Manager.init(std.heap.page_allocator, init.io, .{});
    defer manager.deinit();

    while (true) {
        const status = try manager.update();
        switch (status) {
            .updated, .unchanged => {
                const sample = manager.snapshot() orelse continue;
                std.debug.print(
                    "sim={s} pid={d} speed_mps={?d:.2} gear={?d} rpm={?d:.0} track={?s}\n",
                    .{
                        @tagName(sample.simulator),
                        sample.pid,
                        sample.vehicle.speed_mps,
                        sample.vehicle.gear,
                        sample.vehicle.engine_rpm,
                        sample.identity.track,
                    },
                );
            },
            .idle, .waiting_for_telemetry, .stale, .disconnected => {},
        }
        try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(100), .real);
    }
}
