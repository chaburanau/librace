//! Detection-driven lifecycle manager for all supported simulators.

const std = @import("std");
const detect = @import("../detect/root.zig");
const simulators = @import("../simulators/root.zig");
const adapters = @import("adapters.zig");
const types = @import("types.zig");

const iracing = simulators.iracing;
const ac = simulators.ac;
const acc = simulators.acc;
const ace = simulators.ace;
const acr = simulators.acr;
const ams = simulators.ams;
const ams2 = simulators.ams2;
const fh6 = simulators.fh6;
const lmu = simulators.lmu;
const r3e = simulators.r3e;

pub const UpdateError = iracing.ConnectError ||
    ac.ConnectError ||
    acc.ConnectError ||
    ace.ConnectError ||
    acr.ConnectError ||
    ams.ConnectError ||
    ams2.ConnectError ||
    fh6.ConnectError ||
    fh6.PollError ||
    lmu.ConnectError ||
    r3e.ConnectError;

const Client = union(detect.Simulator) {
    iracing: iracing.Client,
    ac: ac.Client,
    acc: acc.Client,
    ace: ace.Client,
    acr: acr.Client,
    ams: ams.Client,
    ams2: ams2.Client,
    lmu: lmu.Client,
    fh6: fh6.Client,
    r3e: r3e.Client,
};

/// Pointer to the active concrete client. The pointer is invalidated by the
/// next `Manager.update` that disconnects or switches titles, or by `deinit`.
pub const NativeClient = union(detect.Simulator) {
    iracing: *iracing.Client,
    ac: *ac.Client,
    acc: *acc.Client,
    ace: *ace.Client,
    acr: *acr.Client,
    ams: *ams.Client,
    ams2: *ams2.Client,
    lmu: *lmu.Client,
    fh6: *fh6.Client,
    r3e: *r3e.Client,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: types.Options,
    detection: ?detect.Detection = null,
    client: ?Client = null,
    normalized: adapters.State,
    has_snapshot: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: types.Options) Manager {
        return .{
            .allocator = allocator,
            .io = io,
            .options = options,
            .normalized = adapters.State.init(allocator),
        };
    }

    pub fn deinit(self: *Manager) void {
        self.deinitActive();
        self.normalized.deinit();
        self.detection = null;
        self.has_snapshot = false;
    }

    /// Advances detection, connection, polling, normalization, and teardown.
    ///
    /// This function never sleeps on its own. Shared-memory connection waits
    /// and the FH6 receive deadline are controlled through `Options`.
    pub fn update(self: *Manager) UpdateError!types.UpdateStatus {
        if (self.client != null) {
            const current = self.detection orelse unreachable;
            if (!detect.isRunning(current.pid)) {
                self.deinitActive();
                self.detection = null;
                self.has_snapshot = false;
                return .disconnected;
            }
            return self.pollActive(current);
        }

        if (self.detection) |current| {
            if (!detect.isRunning(current.pid)) {
                self.detection = null;
                self.has_snapshot = false;
                return .disconnected;
            }
        } else {
            self.detection = detect.detect(self.options.detection) orelse return .idle;
        }

        const current = self.detection.?;
        if (!try self.connectDetected(current.simulator)) return .waiting_for_telemetry;
        return self.pollActive(current);
    }

    pub fn snapshot(self: *const Manager) ?types.Snapshot {
        if (!self.has_snapshot) return null;
        const current = self.detection orelse return null;
        return self.normalized.snapshot(current.simulator, current.pid);
    }

    pub fn simulator(self: *const Manager) ?detect.Simulator {
        return if (self.detection) |current| current.simulator else null;
    }

    pub fn pid(self: *const Manager) ?u32 {
        return if (self.detection) |current| current.pid else null;
    }

    pub fn native(self: *Manager) ?NativeClient {
        if (self.client) |*client| {
            return switch (client.*) {
                inline else => |*payload, tag| @unionInit(NativeClient, @tagName(tag), payload),
            };
        }
        return null;
    }

    fn connectDetected(self: *Manager, simulator_kind: detect.Simulator) UpdateError!bool {
        const common_options: ac.ConnectOptions = .{
            .timeout = self.options.connect_timeout,
            .retry_interval = self.options.connect_retry_interval,
        };
        switch (simulator_kind) {
            .iracing => {
                const client = iracing.connect(self.allocator, self.io, .{
                    .timeout = self.options.connect_timeout,
                    .retry_interval = self.options.connect_retry_interval,
                    .stale_timeout = self.options.iracing_stale_timeout,
                }) catch |err| return self.connectFailure(err);
                self.client = .{ .iracing = client };
            },
            .ac => self.client = .{ .ac = ac.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .acc => self.client = .{ .acc = acc.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .ace => self.client = .{ .ace = ace.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .acr => self.client = .{ .acr = acr.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .ams => self.client = .{ .ams = ams.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .ams2 => self.client = .{ .ams2 = ams2.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .lmu => self.client = .{ .lmu = lmu.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
            .fh6 => self.client = .{ .fh6 = fh6.connect(self.io, .{ .config = self.options.fh6_config }) catch |err| return self.connectFailure(err) },
            .r3e => self.client = .{ .r3e = r3e.connect(self.allocator, self.io, common_options) catch |err| return self.connectFailure(err) },
        }
        self.normalized.resetClient();
        self.has_snapshot = false;
        return true;
    }

    fn connectFailure(_: *Manager, err: UpdateError) UpdateError!bool {
        return switch (err) {
            error.NotFound, error.MapFailed, error.InvalidHeader, error.Timeout => false,
            else => err,
        };
    }

    fn pollActive(self: *Manager, current: detect.Detection) UpdateError!types.UpdateStatus {
        if (self.client) |*client| {
            return switch (client.*) {
                .iracing => |*value| switch (value.poll()) {
                    .updated => self.didUpdate(current, adapters.normalizeIracing(&self.normalized, value)),
                    .unchanged => if (self.has_snapshot)
                        .unchanged
                    else
                        self.didUpdate(current, adapters.normalizeIracing(&self.normalized, value)),
                    .stale, .rebuild_failed => .stale,
                    .disconnected => self.didDisconnect(),
                },
                .ac => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAc, value),
                .acc => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAcc, value),
                .ace => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAce, value),
                .acr => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAcr, value),
                .ams => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAms, value),
                .ams2 => |*value| self.pollFixed(current, value.poll(), adapters.normalizeAms2, value),
                .lmu => |*value| self.pollFixed(current, value.poll(), adapters.normalizeLmu, value),
                .fh6 => |*value| switch (try value.poll(self.io, self.options.fh6_poll_timeout)) {
                    .ok => self.didUpdate(current, adapters.normalizeFh6(&self.normalized, value)),
                    .stale => .stale,
                    .disconnected => self.didDisconnect(),
                },
                .r3e => |*value| self.pollFixed(current, value.poll(), adapters.normalizeR3e, value),
            };
        }
        unreachable;
    }

    fn pollFixed(
        self: *Manager,
        current: detect.Detection,
        status: anytype,
        comptime normalize: anytype,
        client: anytype,
    ) types.UpdateStatus {
        return switch (status) {
            .ok => self.didUpdate(current, normalize(&self.normalized, client)),
            .stale => .stale,
            .disconnected => self.didDisconnect(),
        };
    }

    fn didUpdate(self: *Manager, _: detect.Detection, normalized_ok: bool) types.UpdateStatus {
        if (!normalized_ok) return .stale;
        self.has_snapshot = true;
        return .updated;
    }

    fn didDisconnect(self: *Manager) types.UpdateStatus {
        self.deinitActive();
        self.detection = null;
        self.has_snapshot = false;
        return .disconnected;
    }

    fn deinitActive(self: *Manager) void {
        if (self.client) |*client| {
            switch (client.*) {
                .fh6 => |*value| value.deinit(self.io),
                inline else => |*value| value.deinit(),
            }
            self.client = null;
            self.normalized.resetClient();
        }
    }
};

test "all detected simulators are represented by client unions" {
    inline for (@typeInfo(detect.Simulator).@"enum".fields) |field| {
        try std.testing.expect(@hasField(Client, field.name));
        try std.testing.expect(@hasField(NativeClient, field.name));
    }
}
