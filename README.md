# librace

SDK for receiving real-time telemetry from racing simulators.

librace is a Zig library that connects to racing games and simulators through whatever channel each title exposes — shared memory, UDP, or other protocols — and exposes live data through each title's native layout.

### Two API shapes

| Shape | Simulators | How you read data |
|-------|------------|-------------------|
| **Dynamic snapshots** | iRacing | Lazy variable-header snapshots, indexed values, and an owned typed session tree |
| **Fixed structs** | AC, ACC, ACE, ACR, AMS, AMS2, BeamNG, LMU, FH6, R3E | Typed snapshots mirroring the wire format (`physics()` / `telemetry()` / `packet()` / `shared()`, etc.); string helpers on `protocol` structs |

Native per-title APIs remain the complete telemetry surface. The optional `librace.unified`
manager provides automatic detection/lifecycle handling and a small normalized common subset.

## Supported simulators

| Simulator | Module | Transport | Status |
|-----------|--------|-----------|--------|
| iRacing | `librace.simulators.iracing` | Shared memory | **Implemented** |
| Assetto Corsa (AC) | `librace.simulators.ac` | Shared memory | **Implemented** |
| Assetto Corsa Competizione (ACC) | `librace.simulators.acc` | Shared memory | **Implemented** |
| Assetto Corsa Evo (ACE) | `librace.simulators.ace` | Shared memory | **Implemented** |
| Assetto Corsa Rally (ACR) | `librace.simulators.acr` | Shared memory | **Implemented** |
| Automobilista (AMS) | `librace.simulators.ams` | Shared memory | **Implemented** |
| Automobilista 2 (AMS2) | `librace.simulators.ams2` | Shared memory | **Implemented** |
| Le Mans Ultimate (LMU) | `librace.simulators.lmu` | Shared memory | **Implemented** |
| BeamNG.drive | `librace.simulators.beamng` | UDP (OutGauge) | **Implemented** |
| Forza Horizon 6 (FH6) | `librace.simulators.fh6` | UDP | **Implemented** |
| RaceRoom Racing Experience (R3E) | `librace.simulators.r3e` | Shared memory | **Implemented** |

More titles will be added over time.

## Requirements

- Zig 0.16.0 or newer
- Windows (shared-memory simulators today; BeamNG / FH6 UDP listeners also target Windows workflows)

## Project layout

```
librace/
├── src/
│   ├── root.zig              # Library entry point
│   ├── core/                 # Shared types and transport helpers
│   ├── detect/               # Process-based "which sim is running?" helpers
│   ├── unified/              # Auto lifecycle + normalized common snapshot
│   └── simulators/           # One folder per simulator
├── build.zig
└── build.zig.zon
```

## Quick start

```bash
# Run library unit tests
zig build test
```

## Using the library

Add librace as a dependency in your `build.zig.zon`, then import the module in your project.

### Unified automatic lifecycle

`librace.unified.Manager` scans for supported simulator processes, connects when telemetry
becomes ready, polls the active title, tears it down when it exits, and detects again. The
caller drives `update()`; the manager creates no thread and performs no hidden sleep.

```zig
var manager = librace.unified.Manager.init(allocator, io, .{});
defer manager.deinit();

while (true) {
    switch (try manager.update()) {
        .updated, .unchanged => {
            const sample = manager.snapshot().?;
            _ = .{
                sample.simulator,
                sample.vehicle.speed_mps,
                sample.vehicle.gear,
                sample.identity.track,
            };

            // Full native telemetry remains available when needed.
            if (manager.native()) |native| switch (native) {
                .iracing => |client| _ = client.variables(),
                else => {},
            };
        },
        .idle, .waiting_for_telemetry, .stale, .disconnected => {},
    }
    try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(100), .real);
}
```

Normalized fields are optional: `null` means that title does not expose a reliable equivalent.
Units are m/s, RPM, liters, seconds, radians, and normalized `0...1` pedal inputs. Gears use
`-1` for reverse, `0` for neutral, and `1+` for forward gears. Identity strings borrow
manager-owned buffers and remain valid until the next `update()` or `deinit()`.

Options include extra process signatures, iRacing stale timeout, and BeamNG/FH6 bind/poll
settings. When a process is visible but telemetry is not ready yet, `update()` returns
`.waiting_for_telemetry`; configuration, version, allocation, and cancellation failures are
returned as errors.

### Detect which simulator is running

`librace.detect` scans processes for known game executables (no shared-memory or UDP probes). Use it to pick a simulator module; each title's `connect` / `poll` handles "running but not telemetry-ready."

```zig
const librace = @import("librace");
const detect = librace.detect;

const d = detect.detect(.{}) orelse return; // null if no known sim process
// d.simulator, d.pid

while (detect.isRunning(d.pid)) {
    // poll your client; sleep between iterations
}
// process exited — call detect() again (do not reuse the old PID)
```

Pass `Options{ .signatures = your_table }` to append extra exe basenames after the built-ins. Matching is case-insensitive and exact (full basename).

### iRacing (dynamic telemetry)

```zig
const librace = @import("librace");
const ir = librace.simulators.iracing;

var client = try ir.connect(allocator, io, .{});
defer client.deinit();

// Name lookup is allocation-free. Cache handles until variables().version() changes.
const speed = (try client.variables().find(ir.keys.var_name.speed)).?;

// Session YAML is copied only when requested and queried without building a tree.
var session = try client.session().snapshot();
defer session.deinit();
const track_value = (try session.query(&.{
    .{ .key = ir.keys.session.weekend_info },
    .{ .key = ir.keys.session.track_display_name },
})).?;
var track_buffer: [128]u8 = undefined;
const track = try track_value.string(&track_buffer);

while (client.waitAndPoll(std.Io.Duration.fromMilliseconds(100)).isOk()) {
    const speed_ms = (try client.variables().value(speed)).asFloat().?;
    _ = .{ speed_ms, track };
}
```

`poll()` returns `updated`, `unchanged`, `stale`, `disconnected`, or `rebuild_failed`. New rows are
copied with torn-read detection; unchanged ticks avoid the copy. Variable lookup and descriptor
iteration allocate nothing, and cached handles read directly from the owned row. A handle becomes
stale only after a catalog change, reconnect, or tick reset. Array values borrow the row until the
next successful update.

Session snapshots make one owned YAML copy. Structured `.key`, `.index`, and `.select` queries scan
only requested branches and allocate nothing; escaped or legacy CP1252 strings use caller storage.
The data-valid event is opened only if `waitAndPoll()` is used. The default no-update liveness
timeout is 30 seconds and can be changed or disabled with `ConnectOptions.stale_timeout`.

Simulator control is independent of telemetry:

```zig
var controller = try ir.Controller.init();
try controller.send(.{ .telemetry_command = .start });
try controller.send(.{ .pit_command = .{ .mode = .fuel, .parameter = 20 } });
```

`ir.enums` mirrors every enum in the current C++ `irsdk_defines.h`, while `ir.commands` exposes
typed packing and a raw forward-compatible send path. Broadcasts are Windows-only and
fire-and-forget; iRacing does not acknowledge command execution.

### Assetto Corsa Evo

AC Evo exposes three fixed shared-memory pages (`physics`, `graphics`, `static`). The client
exposes typed struct snapshots:

```zig
const ace = librace.simulators.ace;

var client = try ace.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const p = client.physics();
    const g = client.graphics();
    const st = client.static() orelse continue;

    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;
    const fuel = p.fuel;
    const track = st.trackName();
    const car = g.carModel();
    _ = .{ speed_kmh, rpm, fuel, track, car };
}
```

### Assetto Corsa

Assetto Corsa exposes three fixed shared-memory pages (`Local\acpmf_physics`,
`Local\acpmf_graphics`, and `Local\acpmf_static`) with UTF-16 `wchar_t` strings:

```zig
const ac = librace.simulators.ac;

var client = try ac.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const p = client.physics();
    const st = client.static().?;

    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;
    const fuel = p.fuel;

    var buf: [96]u8 = undefined;
    const car = st.carModelUtf8(&buf) orelse "?";
    _ = .{ speed_kmh, rpm, fuel, car };
}
```

### Assetto Corsa Competizione

ACC exposes three fixed shared-memory pages under the same map names as classic AC
(`Local\acpmf_physics`, `Local\acpmf_graphics`, and `Local\acpmf_static`) but with
ACC-specific struct layouts:

```zig
const acc = librace.simulators.acc;

var client = try acc.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const p = client.physics();
    const g = client.graphics();
    const st = client.static() orelse continue;

    const speed_kmh = p.speed_kmh;
    const rpm = p.rpm;
    const rain = g.rainIntensityValue().label();

    var buf: [96]u8 = undefined;
    const track = st.trackUtf8(&buf) orelse "?";
    _ = .{ speed_kmh, rpm, rain, track };
}
```

### Assetto Corsa Rally

AC Rally reuses the classic Assetto Corsa shared-memory layout with `wchar_t` (UTF-16LE) strings.
The client exposes typed struct snapshots; `isConnected` keys off the physics `packetId` because
the graphics page is mostly unpopulated by the title:

```zig
const acr = librace.simulators.acr;

var client = try acr.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const p = client.physics();
    const st = client.static() orelse continue;

    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;
    const fuel = p.fuel;

    var buf: [96]u8 = undefined;
    const car = st.carModelUtf8(&buf) orelse "?";
    _ = .{ speed_kmh, rpm, fuel, car };
}
```

> Note: AC Rally currently populates the physics page fully but leaves most of the graphics page
> (status, lap timing) zeroed, so `isConnected` keys off the physics `packetId` rather than the
> graphics `status` flag.

### Le Mans Ultimate

LMU exposes an official native shared-memory page (`LMU_Data`) with player telemetry, session
scoring, and LMU-specific electronics fields. No third-party DLL is required on Windows; enable
plugins in LMU's Gameplay settings.

```zig
const lmu = librace.simulators.lmu;

var client = try lmu.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const t = client.telemetry();
    const s = client.session();

    const speed_kmh = t.speedKmh();
    const rpm = t.engine_rpm;
    const tc = t.tc;

    var buf: [96]u8 = undefined;
    const track = s.trackNameUtf8(&buf) orelse "?";
    _ = .{ speed_kmh, rpm, tc, s.current_et, track };
}
```

### Automobilista

Automobilista exposes the Project CARS 1 shared-memory region (`$pcars$`, SHARED_MEMORY_VERSION 5).
Enable shared memory in the game's hardware / system options. Hot `poll()` copies player/session
fields with a version/speed/rpm consistency check (pCars1 has no sequence number); the participant
grid loads only when `participants()` is called:

```zig
const ams = librace.simulators.ams;

var client = try ams.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();

    const speed_kmh = s.speedKmh();
    const rpm = s.rpm;
    const track = s.trackLocation();
    const car = s.carName();
    _ = .{ speed_kmh, rpm, track, car, client.participants() };
}
```

`connect` returns `error.NotFound` when Automobilista is not running (no `$pcars$` mapping) and
`error.VersionMismatch` if the layout version is incompatible.

### Automobilista 2

AMS2 exposes the Project CARS 2 shared-memory region (`$pcars2$`, SHARED_MEMORY_VERSION 14). Enable
**Options → System → Shared Memory → Project CARS 2**. Hot `poll()` copies player/session fields with
sequence-number torn-read protection; the participant grid loads only when `participants()` is called:

```zig
const ams2 = librace.simulators.ams2;

var client = try ams2.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();

    const speed_kmh = s.speedKmh();
    const rpm = s.rpm;
    const track = s.trackLocation();
    const car = s.carName();
    _ = .{ speed_kmh, rpm, track, car };

    // Optional: competitor grid (copied on demand after each poll)
    const grid = client.participants();
    _ = grid;
}
```

`connect` returns `error.NotFound` when AMS2 is not running (no `$pcars2$` mapping) and
`error.VersionMismatch` if the layout version is incompatible.

### RaceRoom Racing Experience

R3E exposes a single packed shared-memory region (`$R3E`, official API major 3 / minor 5). The client
copies the player/session core on each `poll()`; the 128-entry driver grid is loaded only when
`drivers()` is called:

```zig
const r3e = librace.simulators.r3e;

var client = try r3e.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();

    const speed_kmh = s.speedKmh();
    const rpm = s.engineRpm();
    const track = s.trackName();
    const car = s.vehicle_info.nameUtf8();
    _ = .{ speed_kmh, rpm, track, car };

    // Optional: competitor grid (copied on demand after each poll)
    const grid = client.drivers();
    _ = grid;
}
```

`connect` returns `error.NotFound` when RRRE is not running (no `$R3E` mapping) and
`error.VersionMismatch` if the major version is incompatible.

### BeamNG.drive

BeamNG broadcasts LFS-compatible **OutGauge** UDP datagrams (92 bytes, or 96 with optional ID). Enable **Options → Other → Protocols → OutGauge UDP** (default port `4444`). Disable MotionSim on the same port so its `"BNG1"` packets do not compete. `connect` binds the local UDP port immediately; the timeout passed to `poll` controls how long to wait for telemetry.

```zig
const beamng = librace.simulators.beamng;

var client = try beamng.connect(io, .{});
defer client.deinit(io);

const poll_timeout: std.Io.Timeout = .{ .duration = .{
    .raw = std.Io.Duration.fromMilliseconds(500),
    .clock = .awake,
} };
while (try client.poll(io, poll_timeout) == .ok) {
    const p = client.packet();

    const speed_kmh = p.speedKmh();
    const rpm = p.rpm;
    const gear = p.displayGear();
    const car = p.carName(); // BeamNG hardcodes "beam"
    _ = .{ speed_kmh, rpm, gear, car };
}
```

### Forza Horizon 6

FH6 broadcasts a fixed 324-byte UDP datagram while driving. Enable **Settings → HUD and Gameplay → Data Out** (default port `20066`). `connect` binds the local UDP port immediately; the timeout passed to `poll` controls how long to wait for telemetry.

```zig
const fh6 = librace.simulators.fh6;

var client = try fh6.connect(io, .{});
defer client.deinit(io);

const poll_timeout: std.Io.Timeout = .{ .duration = .{
    .raw = std.Io.Duration.fromMilliseconds(500),
    .clock = .awake,
} };
while (try client.poll(io, poll_timeout) == .ok) {
    const p = client.packet();

    var buf: [64]u8 = undefined;
    const speed_kmh = p.speedKmh();
    const rpm = p.current_engine_rpm;
    const gear = p.displayGear();
    const car = p.formatCarSummary(&buf);
    _ = .{ speed_kmh, rpm, gear, car };
}
```

Fixed-struct simulators also export `field_count` (comptime protocol field total) for discovery-style display.

See [AGENTS.md](AGENTS.md) for SDK design philosophy, IRSDK notes, and implementation workflow.

## License

See [LICENSE](LICENSE).
