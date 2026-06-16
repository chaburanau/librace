const std = @import("std");
const librace = @import("librace");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_buffer: [256]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const sim = librace.simulators.acr;
    try stdout.print("librace example: {s}\n", .{sim.name});
    try stdout.print("Transport: {s}\n", .{@tagName(sim.transport)});
    try stdout.print("Status: not yet implemented — waiting for simulator connection.\n", .{});
    try stdout.flush();
}
