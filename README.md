# librace

SDK for receiving real-time telemetry from racing simulators.

librace is a Zig library that connects to racing games and simulators through whatever channel each title exposes — shared memory, UDP, or other protocols — and exposes live data through each title's native layout.

### Two API shapes

| Shape | Simulators | How you read data |
|-------|------------|-------------------|
| **Dynamic snapshots** | iRacing | Lazy variable-header snapshots, indexed values, and an owned typed session tree |
| **Fixed structs** | AC, ACC, ACE, ACR, AMS2, LMU, FH6, R3E | Typed snapshots mirroring the wire format (`physics()` / `telemetry()` / `packet()` / `shared()`, etc.); string helpers on `protocol` structs |

The SDK does not bake in a shared `Telemetry { speed, gear, … }` struct — callers read the fields they need from protocol layouts or snapshots.

## Supported simulators

| Simulator | Module | Transport | Status |
|-----------|--------|-----------|--------|
| iRacing | `librace.simulators.iracing` | Shared memory | **Implemented** |
| Assetto Corsa (AC) | `librace.simulators.ac` | Shared memory | **Implemented** |
| Assetto Corsa Competizione (ACC) | `librace.simulators.acc` | Shared memory | **Implemented** |
| Assetto Corsa Evo (ACE) | `librace.simulators.ace` | Shared memory | **Implemented** |
| Assetto Corsa Rally (ACR) | `librace.simulators.acr` | Shared memory | **Implemented** |
| Automobilista 2 (AMS2) | `librace.simulators.ams2` | Shared memory | **Implemented** |
| Le Mans Ultimate (LMU) | `librace.simulators.lmu` | Shared memory | **Implemented** |
| Forza Horizon 6 (FH6) | `librace.simulators.fh6` | UDP | **Implemented** |
| RaceRoom Racing Experience (R3E) | `librace.simulators.r3e` | Shared memory | **Implemented** |

More titles will be added over time.

## Requirements

- Zig 0.16.0 or newer
- Windows (shared-memory simulators today; FH6 UDP listener also targets Windows workflows)

## Project layout

```
librace/
├── src/
│   ├── root.zig              # Library entry point
│   ├── core/                 # Shared types and transport helpers
│   └── simulators/           # One folder per simulator
├── examples/
│   ├── common/               # Shared simple + dashboard runners
│   ├── dashboard/            # Legacy dashboard entry (build.zig wires per-sim providers)
│   └── <name>/               # simple.zig + dashboard.zig per simulator
├── build.zig
└── build.zig.zon
```

## Quick start

```bash
# Run library unit tests
zig build test

# Build all example binaries (installed to zig-out/bin/)
zig build

# Simple smoke test (manual check while in a live session)
zig build run-iracing

# Shared terminal dashboard — pick simulator at build time
zig build dashboard -Dsim=iracing
zig build dashboard -Dsim=ac
zig build dashboard -Dsim=acc
zig build dashboard -Dsim=ace
zig build dashboard -Dsim=acr
zig build dashboard -Dsim=ams2
zig build dashboard -Dsim=lmu
zig build dashboard -Dsim=fh6
zig build dashboard -Dsim=r3e

# Or use the per-sim run step directly:
zig build run-dashboard-ac
```

### Example types

Each simulator has a **simple** example and a **dashboard** provider under `examples/<name>/dashboard.zig`, built as `dashboard-<name>`.

| Type | Binary | Build step | Purpose |
|------|--------|------------|---------|
| **Simple** | `zig-out/bin/<name>` | `zig build run-<name>` | Connect, poll a few samples, print one machine-readable line (`OK …` / `FAIL …`); exits 0 on success, 1 on failure |
| **Dashboard** | `zig-out/bin/dashboard-<name>` | `zig build run-dashboard-<name>` | Full-screen terminal UI driven by a common `Data` snapshot filled by the selected provider |

Simple example output (iRacing, when connected):

```
OK track=Circuit des 24 Heures du Mans car=Ferrari 499P gear=3 speed_kmh=142.3 rpm=6500 vars=354
```

Stub simulators print `FAIL not_implemented short_name=<name>` and exit with code 1. The dashboard shows a placeholder when the selected provider is not implemented yet.

### Simple build steps

| Simulator | Build step |
|-----------|------------|
| iRacing | `run-iracing` |
| AC | `run-ac` |
| ACC | `run-acc` |
| ACE | `run-ace` |
| ACR | `run-acr` |
| AMS2 | `run-ams2` |
| LMU | `run-lmu` |
| FH6 | `run-fh6` |
| R3E | `run-r3e` |

Dashboard: `zig build run-dashboard-<name>` (or `zig build dashboard -Dsim=<name>`).

## Using the library

Add librace as a dependency in your `build.zig.zon`, then import the module in your project.

### iRacing (dynamic telemetry)

```zig
const librace = @import("librace");
const ir = librace.simulators.iracing;

var client = try ir.connect(allocator, io, .{});
defer client.deinit();

// To wait for the simulator to start:
// var client = try ir.connect(allocator, io, .{ .timeout = std.Io.Duration.fromSeconds(30) });

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

var client = try ace.connect(allocator, io, .{});
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

var client = try ac.connect(allocator, io, .{});
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

var client = try acc.connect(allocator, io, .{});
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

var client = try acr.connect(allocator, io, .{});
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

var client = try lmu.connect(allocator, io, .{});
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

### Automobilista 2

AMS2 exposes the Project CARS 2 shared-memory region (`$pcars2$`, SHARED_MEMORY_VERSION 14). Enable
**Options → System → Shared Memory → Project CARS 2**. Hot `poll()` copies player/session fields with
sequence-number torn-read protection; the participant grid loads only when `participants()` is called:

```zig
const ams2 = librace.simulators.ams2;

var client = try ams2.connect(allocator, io, .{});
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

var client = try r3e.connect(allocator, io, .{});
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

Fixed-struct simulators also export `field_count` (comptime protocol field total) for discovery-style display in examples.

See [AGENTS.md](AGENTS.md) for SDK design philosophy, IRSDK notes, and implementation workflow.

## License

See [LICENSE](LICENSE).
