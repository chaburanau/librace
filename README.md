# librace

SDK for receiving real-time telemetry from racing simulators.

librace is a Zig library that connects to racing games and simulators through whatever channel each title exposes — shared memory, UDP, or other protocols — and gives you a consistent way to read live data (speed, lap times, inputs, session state, and more).

## Supported simulators

| Simulator | Module | Transport | Status |
|-----------|--------|-----------|--------|
| iRacing | `librace.simulators.iracing` | Shared memory | Planned |
| Assetto Corsa (AC) | `librace.simulators.ac` | Shared memory | Planned |
| Assetto Corsa Competizione (ACC) | `librace.simulators.acc` | Shared memory + UDP | Planned |
| Assetto Corsa Evo (ACE) | `librace.simulators.ace` | Shared memory | Planned |
| Assetto Corsa Rally (ACR) | `librace.simulators.acr` | Shared memory | Planned |
| Le Mans Ultimate (LMU) | `librace.simulators.lmu` | Shared memory | Planned |

More titles will be added over time.

## Requirements

- Zig 0.16.0 or newer

## Project layout

```
librace/
├── src/
│   ├── root.zig              # Library entry point
│   ├── core/                   # Shared types and transport helpers
│   │   ├── types.zig
│   │   └── transport/        # mmap, UDP, and future transports
│   └── simulators/             # One folder per simulator
│       ├── iracing/
│       ├── ac/
│       ├── acc/
│       └── ...
├── examples/                   # Runnable programs (dev smoke tests)
│   ├── iracing/main.zig
│   └── ...
├── build.zig
└── build.zig.zon
```

## Quick start

```bash
# Run tests
zig build test

# Build all example binaries (installed to zig-out/bin/)
zig build

# Run an example while a simulator is running (once implemented)
zig build run-iracing
zig build run-ac
zig build run-acc
zig build run-ace
zig build run-acr
zig build run-lmu
```

## Using the library

Add librace as a dependency in your `build.zig.zon`, then import the module in your project:

```zig
const librace = @import("librace");

// Shared types and transport helpers
const core = librace.core;

// Per-simulator APIs (stubs today; full APIs as each title is implemented)
const iracing = librace.simulators.iracing;
```

## Examples

Each simulator has a matching example under `examples/<name>/`. These programs connect to the running game and print live telemetry. They are the primary manual test during development — run the matching example with the simulator on track to verify parsing and timing.

## License

See [LICENSE](LICENSE).
