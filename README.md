# librace

SDK for receiving real-time telemetry from racing simulators.

librace is a Zig library that connects to racing games and simulators through whatever channel each title exposes — shared memory, UDP, or other protocols — and gives you a consistent way to read live data (speed, lap times, inputs, session state, and more).

## Supported simulators

| Simulator | Module | Transport | Status |
|-----------|--------|-----------|--------|
| iRacing | `librace.simulators.iracing` | Shared memory | **Implemented** |
| Assetto Corsa (AC) | `librace.simulators.ac` | Shared memory | **Implemented** |
| Assetto Corsa Competizione (ACC) | `librace.simulators.acc` | Shared memory | **Implemented** |
| Assetto Corsa Evo (ACE) | `librace.simulators.ace` | Shared memory | **Implemented** |
| Assetto Corsa Rally (ACR) | `librace.simulators.acr` | Shared memory | **Implemented** |
| Le Mans Ultimate (LMU) | `librace.simulators.lmu` | Shared memory | **Implemented** |

More titles will be added over time.

## Requirements

- Zig 0.16.0 or newer
- Windows (for named shared-memory telemetry today)

## Project layout

```
librace/
├── src/
│   ├── root.zig              # Library entry point
│   ├── core/                 # Shared types and transport helpers
│   └── simulators/           # One folder per simulator
├── examples/
│   ├── common/               # Shared simple + dashboard runners
│   ├── dashboard/            # Single dashboard binary + per-sim providers
│   ├── iracing/
│   │   └── simple.zig        # Smoke test (machine-readable output)
│   └── <name>/               # simple.zig for each simulator
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
zig build dashboard -Dsim=lmu
```

### Example types

Each simulator has a **simple** example; the **dashboard** is one shared program with per-sim **providers** under `examples/dashboard/providers/`.

| Type | Binary | Build step | Purpose |
|------|--------|------------|---------|
| **Simple** | `zig-out/bin/<name>` | `zig build run-<name>` | Connect, poll a few samples, print one machine-readable line (`OK …` / `FAIL …`); exits 0 on success, 1 on failure |
| **Dashboard** | `zig-out/bin/dashboard` | `zig build dashboard -Dsim=<name>` | Full-screen terminal UI driven by a common `Data` snapshot filled by the selected provider |

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
| LMU | `run-lmu` |

Dashboard: `zig build dashboard -Dsim=<name>` for any short name above.

## Using the library

Add librace as a dependency in your `build.zig.zon`, then import the module in your project:

```zig
const librace = @import("librace");
const ir = librace.simulators.iracing;

var client = try ir.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    // Strict typed read, or lenient numeric read.
    const gear = try client.getAs(i32, ir.keys.var_name.gear);
    const speed = client.getNumber(ir.keys.var_name.speed) orelse 0;

    // Session metadata. Use playerDriverGet for the player's car in multi-car sessions.
    const track = client.sessionGet(ir.keys.session.track_display_name);
    const car = client.playerDriverGet(ir.keys.driver.car_screen_name);
    _ = .{ gear, speed, track, car };
}
```

For hot loops, resolve a [`VarHandle`] once and read many times, or bind a typed struct whose
field names match IRSDK variable names:

```zig
const Telemetry = struct { Speed: f32 = 0, Gear: i32 = 0, RPM: f32 = 0 };

var telemetry = client.bind(Telemetry);
while (client.poll() == .ok) {
    telemetry.update();
    const v = telemetry.values; // v.Speed, v.Gear, v.RPM
    _ = v;
}
```

### Assetto Corsa Evo

AC Evo exposes three fixed shared-memory pages (`physics`, `graphics`, `static`). The client
gives typed struct access alongside generic name-based lookup and discovery:

```zig
const ace = librace.simulators.ace;

var client = try ace.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    // Typed struct access — the most direct route for AC Evo's fixed layout.
    const p = client.physics();
    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;

    // Generic name-based access over the comptime field catalog.
    const fuel = client.getNumber(ace.keys.physics.fuel) orelse 0;

    // Session metadata (static + graphics pages).
    const track = client.trackName();
    const car = client.carModel();
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
    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;

    const fuel = client.getNumber(ac.keys.physics.fuel) orelse 0;

    var buf: [96]u8 = undefined;
    const car = client.getString(ac.keys.static.car_model, &buf) orelse "?";
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

    const speed_kmh = p.speed_kmh;
    const rpm = p.rpm;
    const rain = g.rainIntensityValue().label();

    var buf: [96]u8 = undefined;
    const track = client.getString(acc.keys.static.track, &buf) orelse "?";
    _ = .{ speed_kmh, rpm, rain, track };
}
```

### Assetto Corsa Rally

AC Rally reuses the classic Assetto Corsa shared-memory layout (`Local\acpmf_physics` /
`acpmf_graphics` / `acpmf_static`) with `wchar_t` (UTF-16LE) strings. The client mirrors the
AC Evo shape — typed struct access plus a generic name-based catalog — but string lookups take a
caller buffer because the values are UTF-16:

```zig
const acr = librace.simulators.acr;

var client = try acr.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    // Typed struct access over the fixed physics page.
    const p = client.physics();
    const speed_kmh = p.speed_kmh;
    const rpm = p.rpms;

    // Generic name-based access over the comptime field catalog.
    const fuel = client.getNumber(acr.keys.physics.fuel) orelse 0;

    // wchar_t strings decode into a caller-supplied UTF-8 buffer.
    var buf: [96]u8 = undefined;
    const car = client.getString(acr.keys.static.car_model, &buf) orelse "?";
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
    const track = client.getString(lmu.keys.session.track_name, &buf) orelse "?";
    _ = .{ speed_kmh, rpm, tc, s.current_et, track };
}
```

See [AGENTS.md](AGENTS.md) for SDK design philosophy, IRSDK notes, and implementation workflow.

## License

See [LICENSE](LICENSE).
