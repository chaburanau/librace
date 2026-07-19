# AGENTS.md — librace

Guidance for AI agents working in this repository.

## What this project is

librace is a **Zig SDK** for **real-time racing simulator telemetry**. Consumers connect to a running simulator and read live data (speed, position, lap info, inputs, session state, etc.).

Each simulator uses different transports and data layouts. This library abstracts those differences behind per-title modules while sharing common infrastructure in `src/core/`.

### Two API shapes

| Shape | Simulators | Primary access |
|-------|------------|----------------|
| **Dynamic snapshots** | iRacing | Allocation-free variable handles, owned telemetry rows, and lazy session queries |
| **Fixed structs** | AC, ACC, ACE, ACR, AMS2, LMU, FH6, R3E | Typed snapshots (`physics()`, `telemetry()`, `packet()`, `shared()`, …); string helpers on `protocol` structs |

Do not add a shared `Telemetry { speed, gear, … }` struct to the SDK — callers read what they need from native layouts or snapshots.

## Repository layout

```
src/
  root.zig                 # Public API: re-exports core + simulators
  core/
    types.zig              # Cross-simulator enums and shared types
    transport/
      mmap.zig             # Shared-memory / memory-mapped file helpers
      udp.zig              # UDP listener helpers
  simulators/
    root.zig               # Re-exports all simulator modules
    <short-name>/
      root.zig             # Public API for that title
      protocol.zig         # Wire format structs/constants
      client.zig           # Connect / poll / parse logic
      session.zig          # (optional) semi-static session metadata parsing
      keys.zig             # (iRacing only) commonly used map/name constants

examples/
  common/
    root.zig               # Re-exports simple, dashboard, stub helpers
    simple.zig             # Smoke-test runner (OK/FAIL output, comptime hooks)
    dashboard.zig          # Terminal dashboard runner (common Data + render)
    dashboard_main.zig     # Shared dashboard executable entry (imports per-sim provider)
    stub.zig               # not_implemented hooks for unimplemented simulators
  <short-name>/
    simple.zig             # Minimal connect + poll example (comptime hooks)
    dashboard.zig          # Dashboard provider (connect/poll/fillData hooks)

build.zig                  # Library module + simple per sim + unified dashboard + tests
build.zig.zon
```

### Simulator short names

| Short name | Game |
|------------|------|
| `iracing` | iRacing |
| `ac` | Assetto Corsa |
| `acc` | Assetto Corsa Competizione |
| `ace` | Assetto Corsa Evo |
| `acr` | Assetto Corsa Rally |
| `ams2` | Automobilista 2 |
| `lmu` | Le Mans Ultimate |
| `fh6` | Forza Horizon 6 |
| `r3e` | RaceRoom Racing Experience |

When adding a new title, use a short lowercase folder name and add it to `src/simulators/root.zig`, `build.zig` (examples list), README, and this file.

## Transport model

Simulators expose telemetry through one or more channels:

- **Memory-mapped / shared memory** — iRacing (`Local\IRSDKMemMapFileName`), AC family physics SDK layouts (`acpmf_*`), LMU native (`LMU_Data`), RaceRoom (`$R3E`), Automobilista 2 (`$pcars2$`), rF2-family plugin buffers.
- **UDP** — FH6 Data Out (324-byte dash packet on a configurable port; default `20066`).
- **Hybrid** — some titles use both; implement whichever channel is needed for complete data.
- **Custom** — reserve `TransportKind.custom` for WebSocket, TCP, or proprietary APIs.

Shared transport code lives in `src/core/transport/`. **Per-simulator byte layouts, field names, and connection lifecycle** live only in `src/simulators/<name>/`.

Do not put simulator-specific struct layouts in `core/`.

## SDK design philosophy

When implementing any simulator module:

1. **Do not assume** what callers need — avoid opinionated structs that pre-parse a fixed field set (no `Telemetry { speed, gear, … }` in the SDK).
2. **Pick the right access model** — **iRacing**: allocation-free caller-cached variable handles, owned row values, and on-demand session queries. **Fixed-layout simulators** (AC family, AMS2, LMU, FH6, R3E): typed struct snapshots mirroring the wire format; string decode helpers live on `protocol` structs.
3. **Provide discovery where it fits** — iRacing exposes a version-checked descriptor iterator with native IRSDK indices. Fixed-layout simulators export `field_count` (comptime protocol field total).
4. **Provide constants sparingly** — `keys.zig` is for common iRacing map keys and variable names. Fixed-layout simulators use protocol struct field names directly.
5. **Keep parsing minimal** — decode types and copy rows from shared memory or UDP; let callers build higher-level models in their own code.

## IRSDK patterns (iRacing) — useful for other titles

iRacing’s IRSDK is a good reference for **variable-header + row-buffer** shared-memory designs used (with variations) by rF2-family games:

| Item | Value / pattern |
|------|-----------------|
| Map name (Windows) | `Local\IRSDKMemMapFileName` |
| Map size | 1164 × 1024 bytes |
| Header version | `IRSDK_VER = 2` |
| Session metadata | YAML string in shared memory; semi-static; `sessionInfoUpdate` counter |
| Live telemetry | Variable headers (`irsdk_varHeader[]`, 144 bytes each) + **ring of row buffers** (`buf_len` bytes each, up to 4 buffers) |
| Variable types | char/bool (1 B), int/bitfield/float (4 B), double (8 B); little-endian |
| Row selection | Pick buffer with highest `tick_count`; use `tick_count_begin` to detect torn reads |
| Connected check | `status & 1`, confirmed by a successfully copied telemetry row |
| Data-valid event | `Local\IRSDKDataValidEvent` (optional; polling/copy is enough for read-only clients) |

**Implementation notes for similar simulators**

1. Open named shared memory read-only (Windows: `OpenFileMappingW` + `MapViewOfFile`; not the same as `std.Io.File.MemoryMap`, which is file-backed).
2. Parse a fixed header; use offsets inside it — never hard-code full layout sizes beyond the header.
3. Copy and index variable headers only when the caller requests discovery.
4. On each poll, **copy** the active row into owned memory before parsing fields.
5. Session strings (YAML, JSON, etc.) can be handled with lightweight key scanning unless full parsing is required.

Official reference: iRacing SDK `irsdk_defines.h`. Community clients (pyirsdk, node-irsdk) track header extensions not always present in older headers.

## Implementing a simulator (workflow)

Work **one simulator at a time**. Typical steps:

1. **Research** the official or community-documented telemetry interface (shared memory name, UDP port, packet layout, update rate).
2. **Implement connection** in `src/simulators/<name>/` using `core/transport` helpers.
3. **Define protocol structs** for the wire format. For iRacing, keep those structs private and expose validated snapshots.
4. **Expose a small public API** — connect, poll, and either lazy variable/session snapshots (iRacing) or typed snapshots + protocol string helpers (fixed-layout). Do **not** bake opinionated structs that assume what callers need.
5. **Add one simple example** under `examples/<name>/simple.zig` using `examples/common/simple.zig` (comptime hooks).
6. **Add a dashboard provider** under `examples/<name>/dashboard.zig` that implements `connect`, `deinit`, `isConnected`, `poll`, `fillData`, and optionally `connectErrorHint` for the shared `examples/common/dashboard.zig` `Data` snapshot.
7. **Add tests** where parsing can be validated without a live game (fixture bytes, golden files). Live connection remains the examples’ job.

Keep each simulator module self-contained. Prefer reusing `core/transport` over duplicating socket or mmap logic.

### iRacing public API (implemented)

Design: polling copies only new telemetry rows. Variable lookup returns allocation-free handles,
and session snapshots keep one owned YAML copy queried without constructing a tree.

```zig
const ir = librace.simulators.iracing;

var client = try ir.connect(allocator, io, .{});
defer client.deinit();

const speed = (try client.variables().find(ir.keys.var_name.speed)).?;

var session = try client.session().snapshot();
defer session.deinit();
const track_scalar = (try session.query(&.{
    .{ .key = ir.keys.session.weekend_info },
    .{ .key = ir.keys.session.track_display_name },
})).?;
var track_buf: [128]u8 = undefined;
const track = try track_scalar.string(&track_buf);

while (client.poll().isOk()) {
    const speed_ms = (try client.variables().value(speed)).asFloat().?;
    _ = .{ speed_ms, track };
}
```

`poll()` returns `updated`, `unchanged`, `disconnected`, `stale`, or `rebuild_failed`. Cache handles
while `variables().version()` is unchanged. Reads are allocation-free; arrays borrow the row until
the next update. `waitAndPoll()` lazily opens the data-valid event. Session `.key` / `.index` /
`.select` queries allocate nothing after the one-copy snapshot. Broadcast control is independent
through `Controller`; all C++ IRSDK enums are exported from `enums`. Common keys live in
`simulators/iracing/keys.zig`; test fixtures remain private in `testing.zig`.

### Assetto Corsa public API (implemented)

Design: **typed struct snapshots** as the primary API. Protocol structs mirror the wire layout;
UTF-16 string fields decode via helpers on `Static` and `Graphics` (for example `trackUtf8`).

```zig
const ac = librace.simulators.ac;

var client = try ac.connect(allocator, io, .{});
defer client.deinit();

while (client.poll() == .ok) {
    const p = client.physics();
    const g = client.graphics();
    const st = client.static() orelse continue;

    const speed_kmh = p.speed_kmh;
    const gear = p.gear;
    const session = g.sessionValue().label();

    var buf: [96]u8 = undefined;
    const track = st.trackUtf8(&buf);
    const car = st.carModelUtf8(&buf);
    _ = .{ speed_kmh, gear, session, track, car };
}
```

`poll()` returns a `PollStatus` (`ok` / `disconnected` / `stale`). `protocol.field_count` is a
comptime total of struct fields across the three pages (for discovery-style display).

### RaceRoom Racing Experience public API (implemented)

Design: **typed `shared()` snapshot** of the official `$R3E` packed layout (API major 3 / minor 5).
Hot `poll()` copies only the ~2 KiB core (through `num_cars`); the 128-entry driver grid is copied
only when `drivers()` is requested. UTF-8 string helpers and unit converters live on `Shared` /
`DriverInfo`.

```zig
const r3e = librace.simulators.r3e;

var client = try r3e.connect(allocator, io, .{});
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();
    const speed_kmh = s.speedKmh();
    const rpm = s.engineRpm();
    const track = s.trackName();
    _ = .{ speed_kmh, rpm, track, client.drivers() };
}
```

`connect` returns `error.NotFound` when RRRE is not running and `error.VersionMismatch` on an
incompatible major version.

### Automobilista 2 public API (implemented)

Design: **typed `shared()` snapshot** of the official `$pcars2$` layout (SHARED_MEMORY_VERSION 14).
Hot `poll()` copies player/session fields with `sequence_number` torn-read protection; the 64-entry
participant grid and per-driver arrays load only when `participants()` is requested. UTF-8 string
helpers and unit converters live on `Shared` / `ParticipantInfo`.

```zig
const ams2 = librace.simulators.ams2;

var client = try ams2.connect(allocator, io, .{});
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();
    const speed_kmh = s.speedKmh();
    const rpm = s.rpm;
    const track = s.trackLocation();
    _ = .{ speed_kmh, rpm, track, client.participants() };
}
```

`connect` returns `error.NotFound` when AMS2 is not running (or Shared Memory is not set to
**Project CARS 2**) and `error.VersionMismatch` on an incompatible layout version.

### Fixed-struct simulators (ACC, ACE, ACR, AMS2, LMU, FH6, R3E)

Same pattern as AC: **typed snapshots** as the primary API; no `catalog.zig`, `keys.zig`, or generic
`getAs`/`resolve`/`read` helpers.

| Simulator | Snapshots | String helpers |
|-----------|-----------|----------------|
| ACC | `physics()`, `graphics()`, `static()` | `trackUtf8`, `carModelUtf8`, `playerNameUtf8`, … (UTF-16) |
| ACE | `physics()`, `graphics()`, `static()` | `trackName()`, `carModel()`, `driverName()` (ASCII C strings) |
| ACR | `physics()`, `graphics()`, `static()` | Same UTF-16 helpers as AC; liveness via physics `packetId` |
| AMS2 | `shared()`, optional `participants()` | `trackLocation()`, `carName()`, `playerName()`, `nameUtf8` on `ParticipantInfo` (UTF-8); `speedKmh()` on `Shared` |
| LMU | `telemetry()`, `session()`, `vehicle()` | `trackNameUtf8`, `vehicleNameUtf8`, `driverNameUtf8` (ANSI) |
| FH6 | `packet()` | `speedKmh()`, `displayGear()`, `formatCarSummary()` on the UDP packet struct |
| R3E | `shared()`, optional `drivers()` | `trackName()`, `layoutName()`, `playerName()`, `nameUtf8` on `DriverInfo` (UTF-8); `speedKmh()` / `engineRpm()` on `Shared` |

Each module re-exports `field_count` from `root.zig`. FH6 passes `std.Io` into `poll()` and accepts
`std.Io.Timeout` because telemetry arrives over UDP rather than shared memory.

## Examples

Each simulator has a **simple** example and a **dashboard** provider under `examples/<name>/`. The shared
runner lives in `examples/common/dashboard_main.zig`; build produces `zig-out/bin/dashboard-<name>`.

### Shared modules (`examples/common/`)

| Module | Role |
|--------|------|
| `simple.zig` | Connect/poll loop, comptime hooks, prints `OK track=… car=… gear=…` or `FAIL …`, exits 1 on failure |
| `dashboard.zig` | ANSI terminal dashboard; providers fill a common `Data` snapshot |
| `stub.zig` | `not_implemented` simple hooks for unimplemented simulators |

Keep simulator-specific helpers out of `examples/common/` (e.g. connect-error text lives in `examples/<name>/`).

### Wiring a new simulator dashboard provider

1. Create `examples/<name>/dashboard.zig` with a `Context` struct holding your SDK client.
2. Implement `connect`, `deinit`, `isConnected`, `poll`, `fillData(ctx, *dashboard.Data)`, and optionally `connectErrorHint`.
3. Map protocol fields into the shared `dashboard.Data` fields in `fillData`.
4. Register the provider in `build.zig` (`addDashboardForSim`) when the sim is implemented; until then stubs use `examples/common/stub.zig` via `-Dsim=<name>`.

### Build commands

```bash
zig build test                      # Library unit tests
zig build                           # Build all example binaries
zig build run-<name>                # Simple smoke test
zig build run-dashboard-<name>      # Real-time dashboard for one simulator
zig build dashboard -Dsim=<name>    # Alias for run-dashboard-<name>
```

Example names: `iracing`, `ac`, `acc`, `ace`, `acr`, `ams2`, `lmu`, `fh6`, `r3e`.

Binaries: `zig-out/bin/<name>` (simple), `zig-out/bin/dashboard-<name>` (dashboard).

### Simple example contract

Successful run ends with a single line and exit code 0:

```
OK track=<s> car=<s> gear=<d> speed_kmh=<f> rpm=<f> vars=<d>
```

Failures print `FAIL <reason>` and exit with code 1 (`not_implemented`, `not_connected`, `poll_failed`, etc.). Examples are for manual checks, not CI.

## Conventions

- **Zig version**: `0.16.0+` (see `build.zig.zon`). Use current std APIs (`std.process.Init`, `std.Io`, etc.).
- **Public API**: only symbols reachable from `src/root.zig` (and re-exports) are library surface. Simulator internals stay in submodules.
- **Naming**: `snake_case` for files and Zig identifiers; simulator folders use short names from the table above.
- **Comments**: document non-obvious protocol details (endianness, struct packing, version fields). Avoid narrating obvious code.
- **Scope**: minimal diffs; do not refactor unrelated simulators when implementing one.
- **No secrets**: do not commit credentials, API keys, or proprietary game binaries.

### Zig 0.16 std notes (observed in this repo)

- `std.heap.GeneralPurposeAllocator` removed — use `std.heap.page_allocator`, `ArenaAllocator`, or `SmpAllocator`.
- Sleep: `std.Io.sleep(io, std.Io.Duration.fromMilliseconds(n), .real)` (not `std.Thread.sleep`).
- String trim: `std.mem.trimEnd` (not `trimRight`).
- Enum from int: `@enumFromInt` (not `std.meta.intToEnum`).
- Windows BOOL: use `@enumFromInt(0)` / `@enumFromInt(1)`, not `windows.FALSE`.
- Named shared memory: use kernel32 `OpenFileMappingW` / `MapViewOfFile` in `core/transport/mmap.zig` (platform-specific).

## What not to do

- Do not merge unrelated simulators into one module (AC and ACC have different layouts).
- Do not add dependencies without a clear need; prefer std and platform APIs for mmap/UDP.
- Do not remove or skip updating `examples/<name>/simple.zig` when implementing a simulator; add `examples/<name>/dashboard.zig` for the dashboard.
- Do not change `build.zig.zon` fingerprint unless intentionally forking the package identity.

## Current status

| Simulator | Status |
|-----------|--------|
| `iracing` | **Implemented** — IRSDK shared memory, allocation-free variable handles, lazy session queries, broadcasts, live poll |
| `ace` | **Implemented** — AC Evo three-page shared memory (physics/graphics/static), typed struct snapshots with ASCII string helpers, live poll |
| `ac` | **Implemented** — classic AC three-page shared memory (`acpmf_*`), `wchar_t`/UTF-16 strings, typed struct snapshots (`physics`/`graphics`/`static`) with wstring decode helpers on protocol structs, live poll |
| `acr` | **Implemented** — classic AC three-page shared memory (`acpmf_*`), `wchar_t`/UTF-16 strings, typed struct snapshots with wstring helpers, live poll (physics-`packetId` liveness; graphics page mostly unpopulated by the title) |
| `acc` | **Implemented** — ACC three-page shared memory (`acpmf_*`), ACC v1.8.12 struct layout, `wchar_t`/UTF-16 strings, typed struct snapshots with wstring helpers, live poll |
| `lmu` | **Implemented** — native S397 shared memory (`LMU_Data`), player telemetry/session/scoring snapshots, ANSI strings with decode helpers on protocol structs, live poll |
| `fh6` | **Implemented** — UDP Data Out (324-byte Horizon dash packet), typed `packet()` snapshot access, live poll |
| `ams2` | **Implemented** — official `$pcars2$` shared memory (SHARED_MEMORY_VERSION 14), typed `shared()` snapshot with on-demand `participants()`, UTF-8 string helpers, live poll |
| `r3e` | **Implemented** — official `$R3E` shared memory (API v3.5), typed `shared()` core snapshot with on-demand `drivers()`, UTF-8 string helpers, live poll |

Next work is typically whichever title the user requests — follow the workflow above. rF2-family titles may reuse patterns from the iRacing IRSDK section or LMU's fixed-struct native shared-memory layout, depending on their exposed telemetry interface.
