//! Public Zig mirrors of every enum in the current IRSDK `irsdk_defines.h`.
//!
//! Source baseline: https://github.com/friss/iracing-sdk-js/blob/main/src/cpp/irsdk/irsdk_defines.h
//! C names are recorded on each declaration so spelling-sensitive wire/API mappings remain clear.

const std = @import("std");

/// C: `irsdk_StatusField`.
pub const StatusField = enum(i32) {
    /// C: `irsdk_stConnected`.
    connected = 1,
    _,
};

/// C: `irsdk_VarType`.
pub const VarType = enum(i32) {
    /// C: `irsdk_char`.
    char = 0,
    /// C: `irsdk_bool`.
    bool = 1,
    /// C: `irsdk_int`.
    int = 2,
    /// C: `irsdk_bitField`.
    bit_field = 3,
    /// C: `irsdk_float`.
    float = 4,
    /// C: `irsdk_double`.
    double = 5,
    /// C: `irsdk_ETCount` (sentinel; do not use as a variable type).
    count = 6,
};

/// C: `irsdk_TrkLoc`.
pub const TrackLocation = enum(i32) {
    /// C: `irsdk_NotInWorld`.
    not_in_world = -1,
    /// C: `irsdk_OffTrack`.
    off_track = 0,
    /// C: `irsdk_InPitStall`.
    in_pit_stall = 1,
    /// C: `irsdk_AproachingPits` (original spelling).
    approaching_pits = 2,
    /// C: `irsdk_OnTrack`.
    on_track = 3,
    _,
};

/// C: `irsdk_TrkSurf`.
pub const TrackSurface = enum(i32) {
    /// C: `irsdk_SurfaceNotInWorld`.
    not_in_world = -1,
    /// C: `irsdk_UndefinedMaterial`.
    undefined = 0,
    /// C: `irsdk_Asphalt1Material`.
    asphalt_1 = 1,
    /// C: `irsdk_Asphalt2Material`.
    asphalt_2 = 2,
    /// C: `irsdk_Asphalt3Material`.
    asphalt_3 = 3,
    /// C: `irsdk_Asphalt4Material`.
    asphalt_4 = 4,
    /// C: `irsdk_Concrete1Material`.
    concrete_1 = 5,
    /// C: `irsdk_Concrete2Material`.
    concrete_2 = 6,
    /// C: `irsdk_RacingDirt1Material`.
    racing_dirt_1 = 7,
    /// C: `irsdk_RacingDirt2Material`.
    racing_dirt_2 = 8,
    /// C: `irsdk_Paint1Material`.
    paint_1 = 9,
    /// C: `irsdk_Paint2Material`.
    paint_2 = 10,
    /// C: `irsdk_Rumble1Material`.
    rumble_1 = 11,
    /// C: `irsdk_Rumble2Material`.
    rumble_2 = 12,
    /// C: `irsdk_Rumble3Material`.
    rumble_3 = 13,
    /// C: `irsdk_Rumble4Material`.
    rumble_4 = 14,
    /// C: `irsdk_Grass1Material`.
    grass_1 = 15,
    /// C: `irsdk_Grass2Material`.
    grass_2 = 16,
    /// C: `irsdk_Grass3Material`.
    grass_3 = 17,
    /// C: `irsdk_Grass4Material`.
    grass_4 = 18,
    /// C: `irsdk_Dirt1Material`.
    dirt_1 = 19,
    /// C: `irsdk_Dirt2Material`.
    dirt_2 = 20,
    /// C: `irsdk_Dirt3Material`.
    dirt_3 = 21,
    /// C: `irsdk_Dirt4Material`.
    dirt_4 = 22,
    /// C: `irsdk_SandMaterial`.
    sand = 23,
    /// C: `irsdk_Gravel1Material`.
    gravel_1 = 24,
    /// C: `irsdk_Gravel2Material`.
    gravel_2 = 25,
    /// C: `irsdk_GrasscreteMaterial`.
    grasscrete = 26,
    /// C: `irsdk_AstroturfMaterial`.
    astroturf = 27,
    _,
};

/// C: `irsdk_SessionState`.
pub const SessionState = enum(i32) {
    /// C: `irsdk_StateInvalid`.
    invalid = 0,
    /// C: `irsdk_StateGetInCar`.
    get_in_car = 1,
    /// C: `irsdk_StateWarmup`.
    warmup = 2,
    /// C: `irsdk_StateParadeLaps`.
    parade_laps = 3,
    /// C: `irsdk_StateRacing`.
    racing = 4,
    /// C: `irsdk_StateCheckered`.
    checkered = 5,
    /// C: `irsdk_StateCoolDown`.
    cool_down = 6,
    _,
};

/// C: `irsdk_CarLeftRight`.
pub const CarLeftRight = enum(i32) {
    /// C: `irsdk_LROff`.
    off = 0,
    /// C: `irsdk_LRClear`.
    clear = 1,
    /// C: `irsdk_LRCarLeft`.
    car_left = 2,
    /// C: `irsdk_LRCarRight`.
    car_right = 3,
    /// C: `irsdk_LRCarLeftRight`.
    car_left_and_right = 4,
    /// C: `irsdk_LR2CarsLeft`.
    two_cars_left = 5,
    /// C: `irsdk_LR2CarsRight`.
    two_cars_right = 6,
    _,
};

/// C: `irsdk_PitSvStatus`.
pub const PitServiceStatus = enum(i32) {
    /// C: `irsdk_PitSvNone`.
    none = 0,
    /// C: `irsdk_PitSvInProgress`.
    in_progress = 1,
    /// C: `irsdk_PitSvComplete`.
    complete = 2,
    /// C: `irsdk_PitSvTooFarLeft`.
    too_far_left = 100,
    /// C: `irsdk_PitSvTooFarRight`.
    too_far_right = 101,
    /// C: `irsdk_PitSvTooFarForward`.
    too_far_forward = 102,
    /// C: `irsdk_PitSvTooFarBack`.
    too_far_back = 103,
    /// C: `irsdk_PitSvBadAngle`.
    bad_angle = 104,
    /// C: `irsdk_PitSvCantFixThat`.
    cannot_fix_that = 105,
    _,
};

/// C: `irsdk_PaceMode`.
pub const PaceMode = enum(i32) {
    /// C: `irsdk_PaceModeSingleFileStart`.
    single_file_start = 0,
    /// C: `irsdk_PaceModeDoubleFileStart`.
    double_file_start = 1,
    /// C: `irsdk_PaceModeSingleFileRestart`.
    single_file_restart = 2,
    /// C: `irsdk_PaceModeDoubleFileRestart`.
    double_file_restart = 3,
    /// C: `irsdk_PaceModeNotPacing`.
    not_pacing = 4,
    _,
};

/// C: `irsdk_TrackWetness`.
pub const TrackWetness = enum(i32) {
    /// C: `irsdk_TrackWetness_UNKNOWN`.
    unknown = 0,
    /// C: `irsdk_TrackWetness_Dry`.
    dry = 1,
    /// C: `irsdk_TrackWetness_MostlyDry`.
    mostly_dry = 2,
    /// C: `irsdk_TrackWetness_VeryLightlyWet`.
    very_lightly_wet = 3,
    /// C: `irsdk_TrackWetness_LightlyWet`.
    lightly_wet = 4,
    /// C: `irsdk_TrackWetness_ModeratelyWet`.
    moderately_wet = 5,
    /// C: `irsdk_TrackWetness_VeryWet`.
    very_wet = 6,
    /// C: `irsdk_TrackWetness_ExtremelyWet`.
    extremely_wet = 7,
    _,
};

/// C: `irsdk_IncidentFlags`.
///
/// Report and penalty fields may be combined. C gives both no-report names value zero;
/// `penalty_no_report` is therefore a typed namespace alias because Zig enum tags must be unique.
pub const IncidentFlags = enum(u32) {
    /// C: `irsdk_Incident_RepNoReport`.
    report_no_report = 0x0000,
    /// C: `irsdk_Incident_RepOutOfControl`.
    report_out_of_control = 0x0001,
    /// C: `irsdk_Incident_RepOffTrack`.
    report_off_track = 0x0002,
    /// C: `irsdk_Incident_RepOffTrackOngoing`.
    report_off_track_ongoing = 0x0003,
    /// C: `irsdk_Incident_RepContactWithWorld`.
    report_contact_with_world = 0x0004,
    /// C: `irsdk_Incident_RepCollisionWithWorld`.
    report_collision_with_world = 0x0005,
    /// C: `irsdk_Incident_RepCollisionWithWorldOngoing`.
    report_collision_with_world_ongoing = 0x0006,
    /// C: `irsdk_Incident_RepContactWithCar`.
    report_contact_with_car = 0x0007,
    /// C: `irsdk_Incident_RepCollisionWithCar`.
    report_collision_with_car = 0x0008,
    /// C: `irsdk_Incident_PenZeroX`.
    penalty_zero_x = 0x0100,
    /// C: `irsdk_Incident_PenOneX`.
    penalty_one_x = 0x0200,
    /// C: `irsdk_Incident_PenTwoX`.
    penalty_two_x = 0x0300,
    /// C: `irsdk_Incident_PenFourX`.
    penalty_four_x = 0x0400,
    /// C: `IRSDK_INCIDENT_REP_MASK`.
    report_mask = 0x000000ff,
    /// C: `IRSDK_INCIDENT_PEN_MASK`.
    penalty_mask = 0x0000ff00,
    _,

    /// C: `irsdk_Incident_PenNoReport`.
    pub const penalty_no_report: IncidentFlags = .report_no_report;
};

/// C: `irsdk_EngineWarnings`.
pub const EngineWarnings = enum(u32) {
    /// C: `irsdk_waterTempWarning`.
    water_temperature = 0x0001,
    /// C: `irsdk_fuelPressureWarning`.
    fuel_pressure = 0x0002,
    /// C: `irsdk_oilPressureWarning`.
    oil_pressure = 0x0004,
    /// C: `irsdk_engineStalled`.
    engine_stalled = 0x0008,
    /// C: `irsdk_pitSpeedLimiter`.
    pit_speed_limiter = 0x0010,
    /// C: `irsdk_revLimiterActive`.
    rev_limiter_active = 0x0020,
    /// C: `irsdk_oilTempWarning`.
    oil_temperature = 0x0040,
    /// C: `irsdk_mandRepNeeded`.
    mandatory_repair_needed = 0x0080,
    /// C: `irsdk_optRepNeeded`.
    optional_repair_needed = 0x0100,
    _,
};

/// C: `irsdk_Flags`.
pub const Flags = enum(u32) {
    /// C: `irsdk_checkered`.
    checkered = 0x00000001,
    /// C: `irsdk_white`.
    white = 0x00000002,
    /// C: `irsdk_green`.
    green = 0x00000004,
    /// C: `irsdk_yellow`.
    yellow = 0x00000008,
    /// C: `irsdk_red`.
    red = 0x00000010,
    /// C: `irsdk_blue`.
    blue = 0x00000020,
    /// C: `irsdk_debris`.
    debris = 0x00000040,
    /// C: `irsdk_crossed`.
    crossed = 0x00000080,
    /// C: `irsdk_yellowWaving`.
    yellow_waving = 0x00000100,
    /// C: `irsdk_oneLapToGreen`.
    one_lap_to_green = 0x00000200,
    /// C: `irsdk_greenHeld`.
    green_held = 0x00000400,
    /// C: `irsdk_tenToGo`.
    ten_to_go = 0x00000800,
    /// C: `irsdk_fiveToGo`.
    five_to_go = 0x00001000,
    /// C: `irsdk_randomWaving`.
    random_waving = 0x00002000,
    /// C: `irsdk_caution`.
    caution = 0x00004000,
    /// C: `irsdk_cautionWaving`.
    caution_waving = 0x00008000,
    /// C: `irsdk_black`.
    black = 0x00010000,
    /// C: `irsdk_disqualify`.
    disqualify = 0x00020000,
    /// C: `irsdk_servicible` (original spelling).
    serviceable = 0x00040000,
    /// C: `irsdk_furled`.
    furled = 0x00080000,
    /// C: `irsdk_repair`.
    repair = 0x00100000,
    /// C: `irsdk_dqScoringInvalid`.
    disqualified_scoring_invalid = 0x00200000,
    /// C: `irsdk_startHidden`.
    start_hidden = 0x10000000,
    /// C: `irsdk_startReady`.
    start_ready = 0x20000000,
    /// C: `irsdk_startSet`.
    start_set = 0x40000000,
    /// C: `irsdk_startGo`.
    start_go = 0x80000000,
    _,
};

/// C: `irsdk_CameraState`.
pub const CameraState = enum(u32) {
    /// C: `irsdk_IsSessionScreen`.
    is_session_screen = 0x0001,
    /// C: `irsdk_IsScenicActive`.
    is_scenic_active = 0x0002,
    /// C: `irsdk_CamToolActive`.
    camera_tool_active = 0x0004,
    /// C: `irsdk_UIHidden`.
    ui_hidden = 0x0008,
    /// C: `irsdk_UseAutoShotSelection`.
    use_auto_shot_selection = 0x0010,
    /// C: `irsdk_UseTemporaryEdits`.
    use_temporary_edits = 0x0020,
    /// C: `irsdk_UseKeyAcceleration`.
    use_key_acceleration = 0x0040,
    /// C: `irsdk_UseKey10xAcceleration`.
    use_key_10x_acceleration = 0x0080,
    /// C: `irsdk_UseMouseAimMode`.
    use_mouse_aim_mode = 0x0100,
    _,
};

/// C: `irsdk_PitSvFlags`.
pub const PitServiceFlags = enum(u32) {
    /// C: `irsdk_LFTireChange`.
    left_front_tire_change = 0x0001,
    /// C: `irsdk_RFTireChange`.
    right_front_tire_change = 0x0002,
    /// C: `irsdk_LRTireChange`.
    left_rear_tire_change = 0x0004,
    /// C: `irsdk_RRTireChange`.
    right_rear_tire_change = 0x0008,
    /// C: `irsdk_FuelFill`.
    fuel_fill = 0x0010,
    /// C: `irsdk_WindshieldTearoff`.
    windshield_tearoff = 0x0020,
    /// C: `irsdk_FastRepair`.
    fast_repair = 0x0040,
    _,
};

/// C: `irsdk_PaceFlags`.
pub const PaceFlags = enum(u32) {
    /// C: `irsdk_PaceFlagsEndOfLine`.
    end_of_line = 0x0001,
    /// C: `irsdk_PaceFlagsFreePass`.
    free_pass = 0x0002,
    /// C: `irsdk_PaceFlagsWavedAround`.
    waved_around = 0x0004,
    _,
};

/// C: `irsdk_BroadcastMsg`.
pub const BroadcastMessage = enum(i32) {
    /// C: `irsdk_BroadcastCamSwitchPos`.
    camera_switch_position = 0,
    /// C: `irsdk_BroadcastCamSwitchNum`.
    camera_switch_number = 1,
    /// C: `irsdk_BroadcastCamSetState`.
    camera_set_state = 2,
    /// C: `irsdk_BroadcastReplaySetPlaySpeed`.
    replay_set_play_speed = 3,
    /// C: `irsdk_BroadcastReplaySetPlayPosition`.
    replay_set_play_position = 4,
    /// C: `irsdk_BroadcastReplaySearch`.
    replay_search = 5,
    /// C: `irsdk_BroadcastReplaySetState`.
    replay_set_state = 6,
    /// C: `irsdk_BroadcastReloadTextures`.
    reload_textures = 7,
    /// C: `irsdk_BroadcastChatComand` (original spelling).
    chat_command = 8,
    /// C: `irsdk_BroadcastPitCommand`.
    pit_command = 9,
    /// C: `irsdk_BroadcastTelemCommand`.
    telemetry_command = 10,
    /// C: `irsdk_BroadcastFFBCommand`.
    force_feedback_command = 11,
    /// C: `irsdk_BroadcastReplaySearchSessionTime`.
    replay_search_session_time = 12,
    /// C: `irsdk_BroadcastVideoCapture`.
    video_capture = 13,
    /// C: `irsdk_BroadcastLast` (sentinel).
    last = 14,
};

/// C: `irsdk_ChatCommandMode`.
pub const ChatCommandMode = enum(i32) {
    /// C: `irsdk_ChatCommand_Macro`.
    macro = 0,
    /// C: `irsdk_ChatCommand_BeginChat`.
    begin_chat = 1,
    /// C: `irsdk_ChatCommand_Reply`.
    reply = 2,
    /// C: `irsdk_ChatCommand_Cancel`.
    cancel = 3,
};

/// C: `irsdk_PitCommandMode`.
pub const PitCommandMode = enum(i32) {
    /// C: `irsdk_PitCommand_Clear`.
    clear = 0,
    /// C: `irsdk_PitCommand_WS`.
    windshield = 1,
    /// C: `irsdk_PitCommand_Fuel`.
    fuel = 2,
    /// C: `irsdk_PitCommand_LF`.
    left_front = 3,
    /// C: `irsdk_PitCommand_RF`.
    right_front = 4,
    /// C: `irsdk_PitCommand_LR`.
    left_rear = 5,
    /// C: `irsdk_PitCommand_RR`.
    right_rear = 6,
    /// C: `irsdk_PitCommand_ClearTires`.
    clear_tires = 7,
    /// C: `irsdk_PitCommand_FR`.
    fast_repair = 8,
    /// C: `irsdk_PitCommand_ClearWS`.
    clear_windshield = 9,
    /// C: `irsdk_PitCommand_ClearFR`.
    clear_fast_repair = 10,
    /// C: `irsdk_PitCommand_ClearFuel`.
    clear_fuel = 11,
    /// C: `irsdk_PitCommand_TC`.
    tire_compound = 12,
};

/// C: `irsdk_TelemCommandMode`.
pub const TelemetryCommandMode = enum(i32) {
    /// C: `irsdk_TelemCommand_Stop`.
    stop = 0,
    /// C: `irsdk_TelemCommand_Start`.
    start = 1,
    /// C: `irsdk_TelemCommand_Restart`.
    restart = 2,
};

/// C: `irsdk_RpyStateMode`.
pub const ReplayStateMode = enum(i32) {
    /// C: `irsdk_RpyState_EraseTape`.
    erase_tape = 0,
    /// C: `irsdk_RpyState_Last` (sentinel).
    last = 1,
};

/// C: `irsdk_ReloadTexturesMode`.
pub const ReloadTexturesMode = enum(i32) {
    /// C: `irsdk_ReloadTextures_All`.
    all = 0,
    /// C: `irsdk_ReloadTextures_CarIdx`.
    car_index = 1,
};

/// C: `irsdk_RpySrchMode`.
pub const ReplaySearchMode = enum(i32) {
    /// C: `irsdk_RpySrch_ToStart`.
    to_start = 0,
    /// C: `irsdk_RpySrch_ToEnd`.
    to_end = 1,
    /// C: `irsdk_RpySrch_PrevSession`.
    previous_session = 2,
    /// C: `irsdk_RpySrch_NextSession`.
    next_session = 3,
    /// C: `irsdk_RpySrch_PrevLap`.
    previous_lap = 4,
    /// C: `irsdk_RpySrch_NextLap`.
    next_lap = 5,
    /// C: `irsdk_RpySrch_PrevFrame`.
    previous_frame = 6,
    /// C: `irsdk_RpySrch_NextFrame`.
    next_frame = 7,
    /// C: `irsdk_RpySrch_PrevIncident`.
    previous_incident = 8,
    /// C: `irsdk_RpySrch_NextIncident`.
    next_incident = 9,
    /// C: `irsdk_RpySrch_Last` (sentinel).
    last = 10,
};

/// C: `irsdk_RpyPosMode`.
pub const ReplayPositionMode = enum(i32) {
    /// C: `irsdk_RpyPos_Begin`.
    begin = 0,
    /// C: `irsdk_RpyPos_Current`.
    current = 1,
    /// C: `irsdk_RpyPos_End`.
    end = 2,
    /// C: `irsdk_RpyPos_Last` (sentinel).
    last = 3,
};

/// C: `irsdk_FFBCommandMode`.
pub const ForceFeedbackCommandMode = enum(i32) {
    /// C: `irsdk_FFBCommand_MaxForce`.
    max_force = 0,
    /// C: `irsdk_FFBCommand_Last` (sentinel).
    last = 1,
};

/// C: `irsdk_csMode`.
///
/// Non-negative values select `focus_at_driver + car number`.
pub const CameraSwitchMode = enum(i32) {
    /// C: `irsdk_csFocusAtIncident`.
    focus_at_incident = -3,
    /// C: `irsdk_csFocusAtLeader`.
    focus_at_leader = -2,
    /// C: `irsdk_csFocusAtExiting`.
    focus_at_exiting = -1,
    /// C: `irsdk_csFocusAtDriver`.
    focus_at_driver = 0,
    _,
};

/// C: `irsdk_VideoCaptureMode`.
pub const VideoCaptureMode = enum(i32) {
    /// C: `irsdk_VideoCapture_TriggerScreenShot`.
    trigger_screenshot = 0,
    /// C: `irsdk_VideoCaptuer_StartVideoCapture` (original spelling).
    start_video_capture = 1,
    /// C: `irsdk_VideoCaptuer_EndVideoCapture` (original spelling).
    end_video_capture = 2,
    /// C: `irsdk_VideoCaptuer_ToggleVideoCapture` (original spelling).
    toggle_video_capture = 3,
    /// C: `irsdk_VideoCaptuer_ShowVideoTimer` (original spelling).
    show_video_timer = 4,
    /// C: `irsdk_VideoCaptuer_HideVideoTimer` (original spelling).
    hide_video_timer = 5,
};

comptime {
    // Field counts guard exhaustive coverage of all 26 enums in the source header.
    std.debug.assert(std.meta.fields(StatusField).len == 1);
    std.debug.assert(std.meta.fields(VarType).len == 7);
    std.debug.assert(std.meta.fields(TrackLocation).len == 5);
    std.debug.assert(std.meta.fields(TrackSurface).len == 29);
    std.debug.assert(std.meta.fields(SessionState).len == 7);
    std.debug.assert(std.meta.fields(CarLeftRight).len == 7);
    std.debug.assert(std.meta.fields(PitServiceStatus).len == 9);
    std.debug.assert(std.meta.fields(PaceMode).len == 5);
    std.debug.assert(std.meta.fields(TrackWetness).len == 8);
    std.debug.assert(std.meta.fields(IncidentFlags).len == 15);
    std.debug.assert(std.meta.fields(EngineWarnings).len == 9);
    std.debug.assert(std.meta.fields(Flags).len == 26);
    std.debug.assert(std.meta.fields(CameraState).len == 9);
    std.debug.assert(std.meta.fields(PitServiceFlags).len == 7);
    std.debug.assert(std.meta.fields(PaceFlags).len == 3);
    std.debug.assert(std.meta.fields(BroadcastMessage).len == 15);
    std.debug.assert(std.meta.fields(ChatCommandMode).len == 4);
    std.debug.assert(std.meta.fields(PitCommandMode).len == 13);
    std.debug.assert(std.meta.fields(TelemetryCommandMode).len == 3);
    std.debug.assert(std.meta.fields(ReplayStateMode).len == 2);
    std.debug.assert(std.meta.fields(ReloadTexturesMode).len == 2);
    std.debug.assert(std.meta.fields(ReplaySearchMode).len == 11);
    std.debug.assert(std.meta.fields(ReplayPositionMode).len == 4);
    std.debug.assert(std.meta.fields(ForceFeedbackCommandMode).len == 2);
    std.debug.assert(std.meta.fields(CameraSwitchMode).len == 4);
    std.debug.assert(std.meta.fields(VideoCaptureMode).len == 6);

    // At least one boundary/discontinuity assertion per source enum, including every sentinel.
    std.debug.assert(@intFromEnum(StatusField.connected) == 1);
    std.debug.assert(@intFromEnum(VarType.char) == 0 and @intFromEnum(VarType.count) == 6);
    std.debug.assert(@intFromEnum(TrackLocation.not_in_world) == -1 and @intFromEnum(TrackLocation.on_track) == 3);
    std.debug.assert(@intFromEnum(TrackSurface.not_in_world) == -1 and @intFromEnum(TrackSurface.astroturf) == 27);
    std.debug.assert(@intFromEnum(SessionState.invalid) == 0 and @intFromEnum(SessionState.cool_down) == 6);
    std.debug.assert(@intFromEnum(CarLeftRight.off) == 0 and @intFromEnum(CarLeftRight.two_cars_right) == 6);
    std.debug.assert(@intFromEnum(PitServiceStatus.complete) == 2 and @intFromEnum(PitServiceStatus.too_far_left) == 100 and @intFromEnum(PitServiceStatus.cannot_fix_that) == 105);
    std.debug.assert(@intFromEnum(PaceMode.single_file_start) == 0 and @intFromEnum(PaceMode.not_pacing) == 4);
    std.debug.assert(@intFromEnum(TrackWetness.unknown) == 0 and @intFromEnum(TrackWetness.extremely_wet) == 7);
    std.debug.assert(@intFromEnum(IncidentFlags.report_collision_with_car) == 0x0008);
    std.debug.assert(@intFromEnum(IncidentFlags.penalty_no_report) == 0x0000);
    std.debug.assert(@intFromEnum(IncidentFlags.penalty_four_x) == 0x0400 and @intFromEnum(IncidentFlags.penalty_mask) == 0x0000ff00);
    std.debug.assert(@intFromEnum(EngineWarnings.water_temperature) == 0x0001 and @intFromEnum(EngineWarnings.optional_repair_needed) == 0x0100);
    std.debug.assert(@intFromEnum(Flags.checkered) == 0x00000001 and @intFromEnum(Flags.start_go) == 0x80000000);
    std.debug.assert(@intFromEnum(CameraState.is_session_screen) == 0x0001 and @intFromEnum(CameraState.use_mouse_aim_mode) == 0x0100);
    std.debug.assert(@intFromEnum(PitServiceFlags.left_front_tire_change) == 0x0001 and @intFromEnum(PitServiceFlags.fast_repair) == 0x0040);
    std.debug.assert(@intFromEnum(PaceFlags.end_of_line) == 0x0001 and @intFromEnum(PaceFlags.waved_around) == 0x0004);
    std.debug.assert(@intFromEnum(BroadcastMessage.camera_switch_position) == 0 and @intFromEnum(BroadcastMessage.last) == 14);
    std.debug.assert(@intFromEnum(ChatCommandMode.macro) == 0 and @intFromEnum(ChatCommandMode.cancel) == 3);
    std.debug.assert(@intFromEnum(PitCommandMode.clear) == 0 and @intFromEnum(PitCommandMode.tire_compound) == 12);
    std.debug.assert(@intFromEnum(TelemetryCommandMode.stop) == 0 and @intFromEnum(TelemetryCommandMode.restart) == 2);
    std.debug.assert(@intFromEnum(ReplayStateMode.erase_tape) == 0 and @intFromEnum(ReplayStateMode.last) == 1);
    std.debug.assert(@intFromEnum(ReloadTexturesMode.all) == 0 and @intFromEnum(ReloadTexturesMode.car_index) == 1);
    std.debug.assert(@intFromEnum(ReplaySearchMode.to_start) == 0 and @intFromEnum(ReplaySearchMode.last) == 10);
    std.debug.assert(@intFromEnum(ReplayPositionMode.begin) == 0 and @intFromEnum(ReplayPositionMode.last) == 3);
    std.debug.assert(@intFromEnum(ForceFeedbackCommandMode.max_force) == 0 and @intFromEnum(ForceFeedbackCommandMode.last) == 1);
    std.debug.assert(@intFromEnum(CameraSwitchMode.focus_at_incident) == -3 and @intFromEnum(CameraSwitchMode.focus_at_driver) == 0);
    std.debug.assert(@intFromEnum(VideoCaptureMode.trigger_screenshot) == 0 and @intFromEnum(VideoCaptureMode.hide_video_timer) == 5);
}

test "all IRSDK enum declarations are referenced" {
    std.testing.refAllDecls(@This());
}
