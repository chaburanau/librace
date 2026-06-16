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
  <short-name>/root.zig    # One module per title (iracing, ac, acc, …)

examples/
  <short-name>/main.zig    # Runnable smoke test for that simulator

build.zig                  # Library module + per-example executables + tests
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

When adding a new title, use a short lowercase folder name and add it to `src/simulators/root.zig`, `build.zig` (examples list), README, and this file.

## Transport model

Simulators expose telemetry through one or more channels:

- **Memory-mapped / shared memory** — iRacing (`Local\IRSDKMem`), AC family physics SDK layouts, rF2-family titles.
- **UDP** — ACC and others broadcast structured packets on configurable ports.
- **Hybrid** — some titles use both; implement whichever channel is needed for complete data.
- **Custom** — reserve `TransportKind.custom` for WebSocket, TCP, or proprietary APIs.

Shared transport code lives in `src/core/transport/`. **Per-simulator byte layouts, field names, and connection lifecycle** live only in `src/simulators/<name>/`.

Do not put simulator-specific struct layouts in `core/`.

## Implementing a simulator (workflow)

Work **one simulator at a time**. Typical steps:

1. **Research** the official or community-documented telemetry interface (shared memory name, UDP port, packet layout, update rate).
2. **Implement connection** in `src/simulators/<name>/` using `core/transport` helpers.
3. **Define typed structs** for that simulator’s raw and/or normalized telemetry.
4. **Expose a small public API** — e.g. `connect`, `poll`/`read`, `disconnect`, and parsed `Telemetry` struct.
5. **Update the example** in `examples/<name>/main.zig` to connect, loop, and print key fields in real time.
6. **Add tests** where parsing can be validated without a live game (fixture bytes, golden files). Live connection remains the example’s job.

Keep each simulator module self-contained. Prefer reusing `core/transport` over duplicating socket or mmap logic.

## Build commands

```bash
zig build test              # Library unit tests
zig build                   # Build library + all example binaries
zig build run-<name>        # Run example for simulator <name>
```

Example names: `iracing`, `ac`, `acc`, `ace`, `acr`, `lmu`.

Examples are installed to `zig-out/bin/<name>`.

## Conventions

- **Zig version**: `0.16.0+` (see `build.zig.zon`). Use current std APIs (`std.process.Init`, `std.Io`, etc.).
- **Public API**: only symbols reachable from `src/root.zig` (and re-exports) are library surface. Simulator internals stay in submodules.
- **Naming**: `snake_case` for files and Zig identifiers; simulator folders use short names from the table above.
- **Comments**: document non-obvious protocol details (endianness, struct packing, version fields). Avoid narrating obvious code.
- **Scope**: minimal diffs; do not refactor unrelated simulators when implementing one.
- **No secrets**: do not commit credentials, API keys, or proprietary game binaries.

## What not to do

- Do not merge unrelated simulators into one module (AC and ACC have different layouts).
- Do not add dependencies without a clear need; prefer std and platform APIs for mmap/UDP.
- Do not remove or skip updating the matching `examples/<name>/` when implementing a simulator.
- Do not change `build.zig.zon` fingerprint unless intentionally forking the package identity.

## Current status

All listed simulators are **stubs** (`name` + `transport` constants). Implementation has not started. The next work is typically **iRacing** or whichever title the user requests — follow the workflow above.
