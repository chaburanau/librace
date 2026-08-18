//! Built-in process exe basenames used by [`detect`](root.zig).
//!
//! Names are matched case-insensitively against the full exe basename and are
//! best-effort (they may drift across game versions / launchers). Callers can
//! pass extra signatures via `Options` to append to this list.

const types = @import("../core/types.zig");

pub const Signature = struct {
    simulator: types.Simulator,
    exe_name: []const u8,
};

/// Default signatures (aliases allowed per simulator). Matched case-insensitively.
pub const builtin: []const Signature = &.{
    .{ .simulator = .iracing, .exe_name = "iRacingSim64DX11.exe" },
    .{ .simulator = .iracing, .exe_name = "iRacingSim64DX12.exe" },
    .{ .simulator = .iracing, .exe_name = "iRacingSim64Vulkan.exe" },
    .{ .simulator = .ac, .exe_name = "acs.exe" },
    .{ .simulator = .acc, .exe_name = "AssettoCorsaCompetizione.exe" },
    .{ .simulator = .ace, .exe_name = "AssettoCorsaEVO.exe" },
    .{ .simulator = .acr, .exe_name = "acr.exe" },
    .{ .simulator = .ams, .exe_name = "Automobilista.exe" },
    .{ .simulator = .ams2, .exe_name = "AMS2AVX.exe" },
    .{ .simulator = .ams2, .exe_name = "AMS2.exe" },
    .{ .simulator = .lmu, .exe_name = "Le Mans Ultimate.exe" },
    .{ .simulator = .fh6, .exe_name = "ForzaHorizon6.exe" },
    .{ .simulator = .r3e, .exe_name = "RRRE.exe" },
    .{ .simulator = .r3e, .exe_name = "RRRE64.exe" },
    .{ .simulator = .beamng, .exe_name = "BeamNG.drive.exe" },
    .{ .simulator = .beamng, .exe_name = "BeamNG.drive.x64.exe" },
    .{ .simulator = .beamng, .exe_name = "BeamNG.tech.exe" },
    .{ .simulator = .beamng, .exe_name = "BeamNG.tech.x64.exe" },
};
