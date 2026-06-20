# AGENTS.md — librace

Guidance for AI agents working in this repository.

## What this project is

librace is a **Zig SDK** for **real-time racing simulator telemetry**. Consumers connect to a running simulator and read live data (speed, position, lap info, inputs, session state, etc.).

Each simulator uses different transports and data layouts. This library abstracts those differences behind per-title modules while sharing common infrastructure in `src/core/`.

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
      protocol.zig         # (optional) wire format structs/constants
      client.zig           # (optional) connect / poll / parse logic
      session.zig          # (optional) semi-static session metadata parsing
      keys.zig             # (optional) commonly used path/name constants

examples/
  common/
    root.zig               # Re-exports simple, dashboard, stub helpers
    simple.zig             # Smoke-test runner (OK/FAIL output, comptime hooks)
    dashboard.zig          # Terminal dashboard runner (common Data + render)
    stub.zig               # not_implemented hooks for unimplemented simulators
  dashboard/
    main.zig               # Single dashboard executable entry point
    providers/
      iracing.zig          # iRacing Data provider
      stub.zig             # Placeholder provider (build-time sim name)
  <short-name>/
    simple.zig             # Minimal connect + poll example (comptime hooks)

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
| `lmu` | Le Mans Ultimate |
| `fh6` | Forza Horizon 6 |

When adding a new title, use a short lowercase folder name and add it to `src/simulators/root.zig`, `build.zig` (examples list), README, and this file.

## Transport model

Simulators expose telemetry through one or more channels:

- **Memory-mapped / shared memory** — iRacing (`Local\IRSDKMemMapFileName`), AC family physics SDK layouts, LMU native (`LMU_Data`), rF2-family plugin buffers.
- **UDP** — ACC and others broadcast structured packets on configurable ports.
- **Hybrid** — some titles use both; implement whichever channel is needed for complete data.
- **Custom** — reserve `TransportKind.custom` for WebSocket, TCP, or proprietary APIs.

Shared transport code lives in `src/core/transport/`. **Per-simulator byte layouts, field names, and connection lifecycle** live only in `src/simulators/<name>/`.

Do not put simulator-specific struct layouts in `core/`.

## SDK design philosophy

When implementing any simulator module:

1. **Do not assume** what callers need — avoid opinionated structs that pre-parse a fixed field set (no `Telemetry { speed, gear, … }` in the SDK).
2. **Provide generic access** — lookup live data by key/name; lookup session metadata by path.
3. **Provide discovery** — expose the variable catalog, raw session document/sections, and iterators/callbacks to enumerate names.
4. **Provide constants** — optional `keys.zig` with commonly used paths/names so callers avoid magic strings.
5. **Keep parsing minimal** — decode types and copy rows from shared memory; let callers build higher-level models in their own code.

## IRSDK patterns (iRacing) — useful for other titles

iRacing’s IRSDK is a good reference for **catalog + row-buffer** shared-memory designs used (with variations) by rF2-family games:

| Item | Value / pattern |
|------|-----------------|
| Map name (Windows) | `Local\IRSDKMemMapFileName` |
| Map size | 1164 × 1024 bytes |
| Header version | `IRSDK_VER = 2` |
| Session metadata | YAML string in shared memory; semi-static; `sessionInfoUpdate` counter |
| Live telemetry | Variable **catalog** (`irsdk_varHeader[]`, 144 bytes each) + **ring of row buffers** (`buf_len` bytes each, up to 4 buffers) |
| Variable types | char/bool (1 B), int/bitfield/float (4 B), double (8 B); little-endian |
| Row selection | Pick buffer with highest `tick_count`; use `tick_count_begin` to detect torn reads |
| Connected check | `status & 1`; community clients also fall back to reading `SessionNum` when the bit flickers |
| Data-valid event | `Local\IRSDKDataValidEvent` (optional; polling/copy is enough for read-only clients) |

**Implementation notes for similar simulators**

1. Open named shared memory read-only (Windows: `OpenFileMappingW` + `MapViewOfFile`; not the same as `std.Io.File.MemoryMap`, which is file-backed).
2. Parse a fixed header; use offsets inside it — never hard-code full layout sizes beyond the header.
3. Build a name → variable map once per session from the catalog.
4. On each poll, **copy** the active row into owned memory before parsing fields.
5. Session strings (YAML, JSON, etc.) can be handled with lightweight key scanning unless full parsing is required.

Official reference: iRacing SDK `irsdk_defines.h`. Community clients (pyirsdk, node-irsdk) track header extensions not always present in older headers.

## Implementing a simulator (workflow)

Work **one simulator at a time**. Typical steps:

1. **Research** the official or community-documented telemetry interface (shared memory name, UDP port, packet layout, update rate).
2. **Implement connection** in `src/simulators/<name>/` using `core/transport` helpers.
3. **Define protocol structs** for wire format and a per-session variable catalog.
4. **Expose a small public API** — connect, poll, lookup by key/path, and discovery (catalog + session sections). Provide **constants** for common keys/paths; do **not** bake opinionated structs that assume what callers need.
5. **Add one simple example** under `examples/<name>/simple.zig` using `examples/common/simple.zig` (comptime hooks).
6. **Add a dashboard provider** under `examples/dashboard/providers/<name>.zig` that implements `connect`, `deinit`, `isConnected`, `poll`, `fillData`, and `connectErrorHint` for the shared `examples/common/dashboard.zig` `Data` snapshot.
7. **Add tests** where parsing can be validated without a live game (fixture bytes, golden files). Live connection remains the examples’ job.

Keep each simulator module self-contained. Prefer reusing `core/transport` over duplicating socket or mmap logic.

### iRacing public API (implemented)

Design: **generic access + discovery + optional constants** (`keys.zig`), with an opt-in typed
layer on top. The SDK bakes in no `Telemetry` or session structs — the caller declares what it needs.

```zig
const ir = librace.simulators.iracing;

var client = try ir.connect(allocator);
// or: ir.waitForConnection(allocator, io, timeout_ms) to wait for the sim to start.
defer client.deinit();

while (client.poll() == .ok) {
    // Telemetry — typed scalar lookup. Errors: NotFound / IsArray / TypeMismatch.
    const gear = try client.getAs(i32, ir.keys.var_name.gear);
    const speed = client.getNumber(ir.keys.var_name.speed); // ?f64, lenient numeric
    const raw = client.getRaw(ir.keys.var_name.lat_accel);  // arrays OK

    // Handles — resolve once, read many (returns error.Stale after a session change).
    const h = client.resolve(ir.keys.var_name.rpm).?;
    const rpm = try client.read(f32, h);

    // Discovery: client.varCount(), client.varDescriptor(i),
    //            client.varNameIterator(), client.sessionSectionIterator(), client.sessionYaml()

    // Session info — any path (Section/Key); player car via DriverCarIdx.
    const track = client.sessionGet(ir.keys.session.track_display_name);
    const car = client.playerDriverGet(ir.keys.driver.car_screen_name);
    _ = .{ gear, speed, raw, rpm, track, car };
}
```

Opt-in typed binding (field names must match IRSDK variable names):

```zig
const Telemetry = struct { Speed: f32 = 0, Gear: i32 = 0, RPM: f32 = 0 };
var telemetry = client.bind(Telemetry);
while (client.poll() == .ok) {
    telemetry.update();
    const v = telemetry.values; // v.Speed, v.Gear, v.RPM
    _ = v;
}
```

`poll()` returns a `PollStatus` (`ok` / `disconnected` / `stale` / `rebuild_failed`).
Common paths and variable names live in `simulators/iracing/keys.zig`. Test-only IRSDK fixture
builders live in `simulators/iracing/testing.zig`, which is intentionally not part of the public API.

## Examples

Each simulator has a **simple** example; the **dashboard** is one program (`examples/dashboard/main.zig`) with per-sim **providers**.

### Shared modules (`examples/common/`)

| Module | Role |
|--------|------|
| `simple.zig` | Connect/poll loop, comptime hooks, prints `OK track=… car=… gear=…` or `FAIL …`, exits 1 on failure |
| `dashboard.zig` | ANSI terminal dashboard; providers fill a common `Data` snapshot |
| `stub.zig` | `not_implemented` simple hooks for unimplemented simulators |

Keep simulator-specific helpers out of `examples/common/` (e.g. connect-error text lives under `examples/iracing/` or in a provider).

### Wiring a new simulator dashboard provider

1. Create `examples/dashboard/providers/<name>.zig` with a `Context` struct holding your SDK client.
2. Implement `connect`, `deinit`, `isConnected`, `poll`, `fillData(ctx, *dashboard.Data)`, and optionally `connectErrorHint`.
3. Map session paths and telemetry keys into the shared `dashboard.Data` fields in `fillData`.
4. Register the provider in `build.zig` (`addDashboardExample`) when the sim is implemented; until then stubs use `providers/stub.zig` via `-Dsim=<name>`.

### Build commands

```bash
zig build test                      # Library unit tests
zig build                           # Build all example binaries
zig build run-<name>                # Simple smoke test
zig build dashboard -Dsim=<name>    # Real-time dashboard for one simulator
```

Example names: `iracing`, `ac`, `acc`, `ace`, `acr`, `lmu`.

Binaries: `zig-out/bin/<name>` (simple), `zig-out/bin/dashboard` (shared dashboard).

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
- Do not remove or skip updating `examples/<name>/simple.zig` when implementing a simulator; add `examples/dashboard/providers/<name>.zig` for the shared dashboard.
- Do not change `build.zig.zon` fingerprint unless intentionally forking the package identity.

## Current status

| Simulator | Status |
|-----------|--------|
| `iracing` | **Implemented** — IRSDK shared memory, variable catalog, session YAML scan, live poll |
| `ace` | **Implemented** — AC Evo three-page shared memory (physics/graphics/static), comptime field catalog, typed + generic access, live poll |
| `ac` | **Implemented** — classic AC three-page shared memory (`acpmf_*`), `wchar_t`/UTF-16 strings, comptime field catalog, typed + generic access, live poll |
| `acr` | **Implemented** — classic AC three-page shared memory (`acpmf_*`), `wchar_t`/UTF-16 strings, comptime field catalog, typed + generic access, live poll (physics-`packetId` liveness; graphics page mostly unpopulated by the title) |
| `acc` | **Implemented** — ACC three-page shared memory (`acpmf_*`), ACC v1.8.12 struct layout, `wchar_t`/UTF-16 strings, comptime field catalog, typed + generic access, live poll |
| `lmu` | **Implemented** — native S397 shared memory (`LMU_Data`), player telemetry/session/scoring snapshots, ANSI strings, comptime field catalog, typed + generic access, live poll |
| `fh6` | **Implemented** — UDP Data Out (324-byte Horizon dash packet), comptime field catalog, typed + generic access, live poll |

Next work is typically whichever title the user requests — follow the workflow above. rF2-family titles may reuse patterns from the iRacing IRSDK section or LMU's fixed-struct native shared-memory catalog, depending on their exposed telemetry interface.
