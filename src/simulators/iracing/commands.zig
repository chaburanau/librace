//! Remote control of iRacing through the IRSDK broadcast Windows message.
//!
//! Definitions mirror the broadcast-related portions of the current
//! `irsdk_defines.h`. Camera and replay commands generally require the session
//! screen; pit commands require the driver to be in the car.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const enums = @import("enums.zig");

pub const broadcast_message_name = "IRSDK_BROADCASTMSG";
pub const broadcast_message_name_w = std.unicode.utf8ToUtf16LeStringLiteral(broadcast_message_name);

pub const BroadcastMessage = enums.BroadcastMessage;
pub const CameraState = enums.CameraState;
pub const ChatCommandMode = enums.ChatCommandMode;
pub const PitCommandMode = enums.PitCommandMode;
pub const TelemetryCommandMode = enums.TelemetryCommandMode;
pub const ReplayStateMode = enums.ReplayStateMode;
pub const ReloadTexturesMode = enums.ReloadTexturesMode;
pub const ReplaySearchMode = enums.ReplaySearchMode;
pub const ReplayPositionMode = enums.ReplayPositionMode;
pub const FfbCommandMode = enums.ForceFeedbackCommandMode;
pub const CameraFocus = enums.CameraSwitchMode;
pub const VideoCaptureMode = enums.VideoCaptureMode;

/// A composable camera-state mask with the same bit layout as `irsdk_CameraState`.
pub const CameraStateFlags = packed struct(u16) {
    is_session_screen: bool = false,
    is_scenic_active: bool = false,
    camera_tool_active: bool = false,
    ui_hidden: bool = false,
    use_auto_shot_selection: bool = false,
    use_temporary_edits: bool = false,
    use_key_acceleration: bool = false,
    use_key_10x_acceleration: bool = false,
    use_mouse_aim_mode: bool = false,
    _reserved: u7 = 0,

    pub fn bits(self: CameraStateFlags) u16 {
        return @bitCast(self);
    }

    pub fn fromFlag(flag: CameraState) CameraStateFlags {
        return @bitCast(@as(u16, @intCast(@intFromEnum(flag))));
    }
};

pub const CameraSwitch = struct {
    /// Car position/number, or one of the negative `CameraFocus` values.
    target: i16,
    group: i16,
    camera: i16,
};

/// Typed forms of every command in `irsdk_BroadcastMsg`.
pub const Command = union(enum) {
    camera_switch_position: CameraSwitch,
    camera_switch_number: CameraSwitch,
    camera_set_state: CameraStateFlags,
    replay_set_play_speed: struct {
        speed: i16,
        slow_motion: bool = false,
    },
    replay_set_play_position: struct {
        mode: ReplayPositionMode,
        frame_number: i32,
    },
    replay_search: ReplaySearchMode,
    replay_set_state: ReplayStateMode,
    reload_textures: struct {
        mode: ReloadTexturesMode,
        car_index: i16 = 0,
    },
    chat_command: struct {
        mode: ChatCommandMode,
        sub_command: i16 = 0,
    },
    pit_command: struct {
        mode: PitCommandMode,
        parameter: i32 = 0,
    },
    telemetry_command: TelemetryCommandMode,
    ffb_command: struct {
        mode: FfbCommandMode,
        value: f32,
    },
    replay_search_session_time: struct {
        session_number: i16,
        session_time_ms: i32,
    },
    video_capture: VideoCaptureMode,
};

/// The three wire values passed through the registered Windows message.
pub const PackedCommand = struct {
    message: i16,
    argument: i16,
    value: u32,

    pub fn wParam(self: PackedCommand) usize {
        return packSigned16(self.message, self.argument);
    }

    pub fn lParam(self: PackedCommand) isize {
        // The SDK passes a 32-bit `int` as LPARAM. Preserve its signed extension
        // on 64-bit Windows as the C conversion does.
        return @as(i32, @bitCast(self.value));
    }
};

pub const PackError = error{FloatOutOfRange};

/// Pack a typed command without sending it.
pub fn pack(command: Command) PackError!PackedCommand {
    return switch (command) {
        .camera_switch_position => |value| short3(
            .camera_switch_position,
            value.target,
            value.group,
            value.camera,
        ),
        .camera_switch_number => |value| short3(
            .camera_switch_number,
            value.target,
            value.group,
            value.camera,
        ),
        .camera_set_state => |value| full32(
            .camera_set_state,
            @as(i16, @bitCast(value.bits())),
            0,
        ),
        .replay_set_play_speed => |value| short3(
            .replay_set_play_speed,
            value.speed,
            @intFromBool(value.slow_motion),
            0,
        ),
        .replay_set_play_position => |value| full32(
            .replay_set_play_position,
            @intCast(@intFromEnum(value.mode)),
            @bitCast(value.frame_number),
        ),
        .replay_search => |value| full32(.replay_search, @intCast(@intFromEnum(value)), 0),
        .replay_set_state => |value| full32(.replay_set_state, @intCast(@intFromEnum(value)), 0),
        .reload_textures => |value| short3(
            .reload_textures,
            @intCast(@intFromEnum(value.mode)),
            value.car_index,
            0,
        ),
        .chat_command => |value| short3(
            .chat_command,
            @intCast(@intFromEnum(value.mode)),
            value.sub_command,
            0,
        ),
        .pit_command => |value| full32(
            .pit_command,
            @intCast(@intFromEnum(value.mode)),
            @bitCast(value.parameter),
        ),
        .telemetry_command => |value| full32(.telemetry_command, @intCast(@intFromEnum(value)), 0),
        .ffb_command => |value| full32(
            .force_feedback_command,
            @intCast(@intFromEnum(value.mode)),
            try packFloat(value.value),
        ),
        .replay_search_session_time => |value| full32(
            .replay_search_session_time,
            value.session_number,
            @bitCast(value.session_time_ms),
        ),
        .video_capture => |value| full32(.video_capture, @intCast(@intFromEnum(value)), 0),
    };
}

/// Pack two signed 16-bit IRSDK arguments like the Win32 `MAKELONG` macro.
pub fn packSigned16(low: i16, high: i16) u32 {
    const low_bits: u16 = @bitCast(low);
    const high_bits: u16 = @bitCast(high);
    return @as(u32, low_bits) | (@as(u32, high_bits) << 16);
}

/// Pack the SDK float overload as signed 16.16 fixed point.
///
/// This intentionally does not bit-cast IEEE-754 bits: the C++ SDK multiplies
/// the float by 65536 and truncates it to a signed 32-bit integer.
pub fn packFloat(value: f32) PackError!u32 {
    const scaled = value * 65536.0;
    if (!std.math.isFinite(scaled) or
        scaled < @as(f32, @floatFromInt(std.math.minInt(i32))) or
        scaled >= 2147483648.0)
    {
        return error.FloatOutOfRange;
    }
    const fixed: i32 = @intFromFloat(scaled);
    return @bitCast(fixed);
}

fn short3(message: BroadcastMessage, argument1: i16, argument2: i16, argument3: i16) PackedCommand {
    return full32(message, argument1, packSigned16(argument2, argument3));
}

fn full32(message: BroadcastMessage, argument: i16, value: u32) PackedCommand {
    return .{
        .message = @intCast(@intFromEnum(message)),
        .argument = argument,
        .value = value,
    };
}

pub const Controller = struct {
    registered_message: u32,

    pub const InitError = error{
        UnsupportedPlatform,
        RegistrationFailed,
    };

    pub const SendError = PackError || error{
        UnsupportedPlatform,
        SendFailed,
    };

    /// Register `IRSDK_BROADCASTMSG` for the current Windows session.
    pub fn init() InitError!Controller {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
        const message = RegisterWindowMessageW(broadcast_message_name_w);
        if (message == 0) return error.RegistrationFailed;
        return .{ .registered_message = message };
    }

    pub fn send(self: Controller, command: Command) SendError!void {
        const encoded = try pack(command);
        return self.sendRaw(encoded.message, encoded.argument, encoded.value);
    }

    /// Send already-packed values, including command IDs added by future SDKs.
    pub fn sendRaw(self: Controller, message: i16, argument: i16, value: u32) SendError!void {
        if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
        const encoded: PackedCommand = .{
            .message = message,
            .argument = argument,
            .value = value,
        };
        const succeeded = SendNotifyMessageW(
            hwnd_broadcast,
            self.registered_message,
            encoded.wParam(),
            encoded.lParam(),
        );
        if (succeeded == @as(windows.BOOL, @enumFromInt(0))) return error.SendFailed;
    }
};

const hwnd_broadcast: windows.HWND = @ptrFromInt(0xffff);

extern "user32" fn RegisterWindowMessageW(
    lpString: [*:0]const u16,
) callconv(.winapi) u32;

extern "user32" fn SendNotifyMessageW(
    hWnd: windows.HWND,
    Msg: u32,
    wParam: usize,
    lParam: isize,
) callconv(.winapi) windows.BOOL;

test "all IRSDK broadcast IDs retain their wire values" {
    try std.testing.expectEqual(@as(i16, 0), @intFromEnum(BroadcastMessage.camera_switch_position));
    try std.testing.expectEqual(@as(i16, 13), @intFromEnum(BroadcastMessage.video_capture));
    try std.testing.expectEqual(@as(i16, 14), @intFromEnum(BroadcastMessage.last));
    try std.testing.expectEqual(@as(i16, 12), @intFromEnum(PitCommandMode.tire_compound));
    try std.testing.expectEqual(@as(i16, 5), @intFromEnum(VideoCaptureMode.hide_video_timer));
}

test "signed 16-bit arguments match MAKELONG" {
    try std.testing.expectEqual(@as(u32, 0xffff8000), packSigned16(std.math.minInt(i16), -1));

    const encoded = try pack(.{ .camera_switch_position = .{
        .target = @intCast(@intFromEnum(CameraFocus.focus_at_incident)),
        .group = 12,
        .camera = -2,
    } });
    try std.testing.expectEqual(@as(i16, 0), encoded.message);
    try std.testing.expectEqual(@as(i16, -3), encoded.argument);
    try std.testing.expectEqual(@as(u32, 0xfffe000c), encoded.value);
    try std.testing.expectEqual(@as(usize, 0xfffd0000), encoded.wParam());
}

test "full 32-bit command values retain their bits" {
    const replay = try pack(.{ .replay_set_play_position = .{
        .mode = .current,
        .frame_number = -123456,
    } });
    try std.testing.expectEqual(@as(i16, 4), replay.message);
    try std.testing.expectEqual(@as(i16, 1), replay.argument);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -123456))), replay.value);
    try std.testing.expectEqual(@as(isize, -123456), replay.lParam());
}

test "float commands use signed 16.16 fixed point" {
    try std.testing.expectEqual(@as(u32, 0x00018000), try packFloat(1.5));
    try std.testing.expectEqual(@as(u32, 0xffff8000), try packFloat(-0.5));
    try std.testing.expectError(error.FloatOutOfRange, packFloat(std.math.inf(f32)));

    const ffb = try pack(.{ .ffb_command = .{ .mode = .max_force, .value = 32.25 } });
    try std.testing.expectEqual(@as(i16, 11), ffb.message);
    try std.testing.expectEqual(@as(u32, 0x00204000), ffb.value);
}

test "camera state flags mirror the IRSDK mask" {
    const camera: CameraStateFlags = .{
        .camera_tool_active = true,
        .ui_hidden = true,
        .use_mouse_aim_mode = true,
    };
    try std.testing.expectEqual(@as(u16, 0x010c), camera.bits());
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(CameraStateFlags));
}

test "controller registers the live IRSDK Windows message" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    _ = try Controller.init();
}
