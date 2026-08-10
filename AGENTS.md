# AGENTS.md — librace

Guidance for AI agents working in this repository.

## What this project is

librace is a **Zig SDK** for **real-time racing simulator telemetry**. Consumers connect to a running simulator and read live data (speed, position, lap info, inputs, session state, etc.).

Each simulator uses different transports and data layouts. This library abstracts those differences behind per-title modules while sharing common infrastructure in `src/core/`.

### Two API shapes

| Shape | Simulators | Primary access |
|-------|------------|----------------|
| **Dynamic snapshots** | iRacing | Allocation-free variable handles, owned telemetry rows, and lazy session queries |
| **Fixed structs** | AC, ACC, ACE, ACR, AMS, AMS2, BeamNG, LMU, FH6, R3E | Typed snapshots (`physics()`, `telemetry()`, `packet()`, `shared()`, …); string helpers on `protocol` structs |

Native layouts and snapshots remain the complete APIs. The opt-in `librace.unified` manager
exposes a deliberately small normalized subset with optional fields and native-client escape
hatches.

## Repository layout

```
src/
  root.zig                 # Public API: re-exports core + detect + unified + simulators
  core/
    types.zig              # Cross-simulator enums and shared types
    transport/
      mmap.zig             # Shared-memory / memory-mapped file helpers
      udp.zig              # UDP listener helpers
  detect/
    root.zig               # detect() / isRunning() — process-scan helpers
    signatures.zig         # Built-in exe basename table
    process.zig            # Windows Toolhelp / OpenProcess helpers
  unified/
    root.zig               # Public normalized types and manager exports
    manager.zig            # Detection-driven lifecycle + native tagged union
    adapters.zig           # Per-title normalized common-subset mappings
  simulators/
    root.zig               # Re-exports all simulator modules
    <short-name>/
      root.zig             # Public API for that title
      protocol.zig         # Wire format structs/constants
      client.zig           # Connect / poll / parse logic
      session.zig          # (optional) semi-static session metadata parsing
      keys.zig             # (iRacing only) commonly used map/name constants

build.zig                  # Library module + tests
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
| `ams` | Automobilista |
| `ams2` | Automobilista 2 |
| `lmu` | Le Mans Ultimate |
| `beamng` | BeamNG.drive |
| `fh6` | Forza Horizon 6 |
| `r3e` | RaceRoom Racing Experience |

When adding a new title, use a short lowercase folder name and add it to `src/simulators/root.zig`, README, and this file.

## Transport model

Simulators expose telemetry through one or more channels:

- **Memory-mapped / shared memory** — iRacing (`Local\IRSDKMemMapFileName`), AC family physics SDK layouts (`acpmf_*`), LMU native (`LMU_Data`), RaceRoom (`$R3E`), Automobilista (`$pcars$`), Automobilista 2 (`$pcars2$`), rF2-family plugin buffers.
- **UDP** — FH6 Data Out (324-byte dash packet on a configurable port; default `20066`); BeamNG OutGauge (LFS-compatible 92/96-byte datagram; default port `4444`).
- **Hybrid** — some titles use both; implement whichever channel is needed for complete data.
- **Custom** — reserve `TransportKind.custom` for WebSocket, TCP, or proprietary APIs.

Shared transport code lives in `src/core/transport/`. **Per-simulator byte layouts, field names, and connection lifecycle** live only in `src/simulators/<name>/`.

Do not put simulator-specific struct layouts in `core/`.

## Process detection (`librace.detect`)

Lightweight Windows helpers to find which known sim **process** is running:

```zig
const d = librace.detect.detect(.{}) orelse return;
_ = librace.detect.isRunning(d.pid);
```

`detect()` matches exe basenames exactly (case-insensitive) from a built-in table, plus any caller-supplied signatures appended via `Options`. `isRunning(pid)` is a non-blocking liveness check. This does **not** probe shared memory or UDP — use each title's `connect` / `poll` for telemetry readiness.

## Unified lifecycle (`librace.unified`)

`Manager.update()` is a caller-driven state machine: detect, connect, poll, normalize, tear down,
and detect again. It must not create a background thread or sleep implicitly. Keep mappings
explicit in `src/unified/adapters.zig`, use canonical units, represent unavailable fields as
`null`, and copy normalized strings into manager-owned buffers. iRacing variable handles are
cached by catalog version and session metadata is refreshed only when its version changes.

Every new `detect.Simulator` variant must be added to the manager client/native unions, lifecycle
switches, and normalized adapters.

## SDK design philosophy

When implementing any simulator module:

1. **Keep native APIs complete** — do not replace protocol snapshots with an opinionated fixed
   field set. Add only reliable common fields to `unified.Snapshot`, make unavailable values
   optional, and preserve native access.
2. **Pick the right access model** — **iRacing**: allocation-free caller-cached variable handles, owned row values, and on-demand session queries. **Fixed-layout simulators** (AC family, AMS, AMS2, BeamNG, LMU, FH6, R3E): typed struct snapshots mirroring the wire format; string decode helpers live on `protocol` structs.
3. **Provide discovery where it fits** — iRacing exposes a version-checked descriptor iterator with native IRSDK indices. Fixed-layout simulators rely on typed protocol structs instead.
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
5. **Add tests** where parsing can be validated without a live game (fixture bytes, golden files).

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

var client = try ac.connect(allocator);
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

`poll()` returns a `PollStatus` (`ok` / `disconnected` / `stale`).

### RaceRoom Racing Experience public API (implemented)

Design: **typed `shared()` snapshot** of the official `$R3E` packed layout (API major 3 / minor 5).
Hot `poll()` copies only the ~2 KiB core (through `num_cars`); the 128-entry driver grid is copied
only when `drivers()` is requested. UTF-8 string helpers and unit converters live on `Shared` /
`DriverInfo`.

```zig
const r3e = librace.simulators.r3e;

var client = try r3e.connect(allocator);
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

### Automobilista public API (implemented)

Design: **typed `shared()` snapshot** of the Project CARS 1 `$pcars$` layout (SHARED_MEMORY_VERSION 5).
Hot `poll()` copies player/session fields with a version/speed/rpm consistency check (no sequence
number in pCars1); the 64-entry participant grid loads only when `participants()` is requested.
UTF-8 string helpers and unit converters live on `Shared` / `ParticipantInfo`.

```zig
const ams = librace.simulators.ams;

var client = try ams.connect(allocator);
defer client.deinit();

while (client.poll() == .ok) {
    const s = client.shared();
    const speed_kmh = s.speedKmh();
    const rpm = s.rpm;
    const track = s.trackLocation();
    _ = .{ speed_kmh, rpm, track, client.participants() };
}
```

`connect` returns `error.NotFound` when Automobilista is not running (or shared memory is disabled)
and `error.VersionMismatch` on an incompatible layout version.

### Automobilista 2 public API (implemented)

Design: **typed `shared()` snapshot** of the official `$pcars2$` layout (SHARED_MEMORY_VERSION 14).
Hot `poll()` copies player/session fields with `sequence_number` torn-read protection; the 64-entry
participant grid and per-driver arrays load only when `participants()` is requested. UTF-8 string
helpers and unit converters live on `Shared` / `ParticipantInfo`.

```zig
const ams2 = librace.simulators.ams2;

var client = try ams2.connect(allocator);
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

### Fixed-struct simulators (ACC, ACE, ACR, AMS, AMS2, BeamNG, LMU, FH6, R3E)

Same pattern as AC: **typed snapshots** as the primary API; no `catalog.zig`, `keys.zig`, or generic
`getAs`/`resolve`/`read` helpers.

| Simulator | Snapshots | String helpers |
|-----------|-----------|----------------|
| ACC | `physics()`, `graphics()`, `static()` | `trackUtf8`, `carModelUtf8`, `playerNameUtf8`, … (UTF-16) |
| ACE | `physics()`, `graphics()`, `static()` | `trackName()`, `carModel()`, `driverName()` (ASCII C strings) |
| ACR | `physics()`, `graphics()`, `static()` | Same UTF-16 helpers as AC; liveness via physics `packetId` |
| AMS | `shared()`, optional `participants()` | `trackLocation()`, `carName()`, `playerName()`, `nameUtf8` on `ParticipantInfo` (UTF-8); `speedKmh()` on `Shared` |
| AMS2 | `shared()`, optional `participants()` | `trackLocation()`, `carName()`, `playerName()`, `nameUtf8` on `ParticipantInfo` (UTF-8); `speedKmh()` on `Shared` |
| LMU | `telemetry()`, `session()`, `vehicle()` | `trackNameUtf8`, `vehicleNameUtf8`, `driverNameUtf8` (ANSI) |
| BeamNG | `packet()` | `carName()`, `display1Text()`, `display2Text()`, `speedKmh()`, `displayGear()` on the OutGauge packet struct |
| FH6 | `packet()` | `speedKmh()`, `displayGear()`, `formatCarSummary()` on the UDP packet struct |
| R3E | `shared()`, optional `drivers()` | `trackName()`, `layoutName()`, `playerName()`, `nameUtf8` on `DriverInfo` (UTF-8); `speedKmh()` / `engineRpm()` on `Shared` |

BeamNG and FH6 pass `std.Io` into `poll()` and accept `std.Io.Timeout` because telemetry arrives
over UDP rather than shared memory.

### Build commands

```bash
zig build test                      # Library unit tests
```

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
| `beamng` | **Implemented** — OutGauge UDP (LFS-compatible 92/96-byte packet, default port 4444), typed `packet()` snapshot access, live poll |
| `fh6` | **Implemented** — UDP Data Out (324-byte Horizon dash packet), typed `packet()` snapshot access, live poll |
| `ams` | **Implemented** — Project CARS 1 `$pcars$` shared memory (SHARED_MEMORY_VERSION 5), typed `shared()` snapshot with on-demand `participants()`, UTF-8 string helpers, live poll |
| `ams2` | **Implemented** — official `$pcars2$` shared memory (SHARED_MEMORY_VERSION 14), typed `shared()` snapshot with on-demand `participants()`, UTF-8 string helpers, live poll |
| `r3e` | **Implemented** — official `$R3E` shared memory (API v3.5), typed `shared()` core snapshot with on-demand `drivers()`, UTF-8 string helpers, live poll |

Next work is typically whichever title the user requests — follow the workflow above. rF2-family titles may reuse patterns from the iRacing IRSDK section or LMU's fixed-struct native shared-memory layout, depending on their exposed telemetry interface.
