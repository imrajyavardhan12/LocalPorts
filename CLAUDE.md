# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
zig build -Doptimize=ReleaseFast
```

Binary outputs to `./zig-out/bin/localports`.

## Architecture

**Platform dispatch** in `src/main.zig:doScan()` uses `builtin.os.tag` to route to the correct backend:
- `.macos` → `src/darwin.zig` (uses libproc syscalls)
- `.linux` → `src/linux.zig` (stub, not yet implemented)

**Core types** in `src/types.zig`: `PortEntry` struct holds port, pid, process name, and address info.

**Output formatting** in `src/output.zig`: `writeTable()` for human-readable output, `writeJson()` for JSON.

**Platform backends**: `src/darwin.zig` implements the port scanner using macOS libproc (`proc_listallpids`, `proc_pidinfo`, `proc_pidfdinfo`). It uses compile-time size assertions to validate C struct layouts match `sys/proc_info.h`.

## CLI Interface

```bash
localports [port]           # Filter by port
localports --port, -p <port> # Filter by port
localports --json           # JSON output
localports --help, -h       # Show help
localports --version, -v    # Show version
```

Run with `sudo` to see all system processes.

## Homebrew Distribution

Release workflow builds and publishes to a custom Homebrew tap at `imrajyavardhan12/localports`. The formula is in `Formula/localports.rb` and builds using `zig build -Doptimize=ReleaseFast`.
