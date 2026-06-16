# Changelog

## Unreleased

### Added

- Network-exposure awareness. Listeners bound to a non-loopback address
  (`0.0.0.0`, `::`, or a real interface address — reachable from your network)
  are tagged `! network` in the table, while loopback-only rows stay clean. A new
  `--exposed` flag filters a scan (or `--watch`) to just those network-reachable
  listeners — a quick "what on this machine is reachable from outside?" check.
  This reflects the bind scope only; a firewall may still block inbound traffic.

### Fixed

- IPv6 addresses now display in their canonical RFC 5952 form (lowercase, leading
  zeros suppressed, the longest run of zero groups collapsed to `::`) in both the
  table and JSON output — e.g. `::1` instead of
  `0000:0000:0000:0000:0000:0000:0000:0001`.

## 0.5.3 - 2026-06-14

### Changed

- Homebrew now installs a prebuilt, self-contained binary instead of compiling
  from source. The formula downloads a per-architecture release binary
  (cross-compiled with Zig, links only `/usr/lib/libSystem`) and no longer
  depends on the `zig`/LLVM build toolchain, so `brew install localports` is
  near-instant and pulls no build dependencies. After upgrading, an existing
  source install can reclaim the toolchain (~1.8 GB) with `brew autoremove`.

### Added

- Release workflow cross-compiles macOS arm64 and x86_64 binaries, smoke-tests
  the arm64 artifact, uploads them as release assets, and templates the tap
  formula from them. CI exercises the same packaging on every push.

## 0.5.2 - 2026-06-14

### Added

- macOS scanner integration test that binds a real TCP listener and verifies
  the scanner discovers it through the full libproc path.
- CI checks for shell completion/man page/formula syntax and CLI flag drift
  across help text, completions, and the man page.

### Fixed

- Watch mode now honors the `--verbose`, `--tree`, and `--docker` display
  flags. They were previously accepted but silently ignored under `--watch`,
  which only ever rendered the base PORT/PID/PROCESS/ADDRESS table; the
  enrichment columns now refresh on every cycle just as they do for one-shot
  scans.
- Watch mode no longer destroys the terminal scrollback buffer on each
  refresh. The clear-screen sequence now uses ED 0 (clear from cursor to
  end of screen) instead of ED 2 (clear entire screen), matching the
  behavior of `top`, `htop`, and `watch`.

## 0.5.1 - 2026-06-06

### Changed

- Optimized macOS scanner deduplication from a linear scan over collected
  entries to a hash-set lookup while preserving the existing `(port, pid)`
  behavior.

### Fixed

- Port-based kill commands now refuse Docker host-process targets so
  `localports --kill <port>` does not accidentally kill Docker Desktop instead
  of the container publishing the port. The message suggests `docker stop` when
  the container can be resolved.

## 0.5.0 - 2026-06-06

### Added

- Shell completions for zsh, bash, and fish.
- A `localports(1)` man page, installed by Homebrew and `zig build install`.

### Fixed

- `--tree` now uses BSD process info for ancestor names, avoiding `?` when
  `proc_name` cannot resolve a parent and reducing ancestry lookup syscalls.
- `--docker` now expands published port ranges such as
  `8000-8002->80-82/tcp`.
- `--docker` now times out the `docker ps` subprocess instead of waiting
  forever on a hung Docker daemon.

## 0.4.0 - 2026-06-06

### Added

- `--docker` resolves a port held by a Docker process (`com.docker.backend`
  and friends) to the actual container, showing a `CONTAINER` column
  (`name (image ->container_port)`) in the table and a `container` object in
  JSON. It shells out to `docker ps` once, only when a Docker-owned port is
  present, and degrades silently if docker is missing or the daemon is down.
  Scan-only; adds output only under the flag.
- `--tree` shows each listener's parent-process chain (immediate parent up
  toward launchd), rendered as an indented tree in the table and as an
  `ancestors` array in JSON. Composes with `--verbose`. Like other display
  flags it is scan-only and adds JSON fields only under the flag, leaving the
  default contract unchanged.

## 0.3.0 - 2026-06-05

### Added

- Kill controls for multi-process ports. `--kill <port> --all` kills every
  process on the port; `--kill <port> --pid <pid>` kills that pid only if it
  is listening on the port; `--kill-pid <pid>` kills a process by explicit
  PID. The default `--kill <port>` still refuses ambiguous multi-process
  matches, and all kills require confirmation unless `--force` is given.
- `--verbose` shows the owning user and full command line for each listener,
  in both table and JSON output. The command line is resolved via
  `KERN_PROCARGS2` and the user via `getpwuid`; fields that require ownership
  fall back to `-` (table) or `""` (JSON) without sudo. Verbose JSON fields
  are added only under `--json --verbose`, leaving the default JSON contract
  unchanged for scripts.

### Fixed

- macOS scanner no longer silently truncates results. The PID list and each
  process's file-descriptor list are now sized dynamically (libproc
  two-call idiom with headroom) instead of using fixed 4096-PID / 2048-FD
  buffers, so listeners are no longer dropped on busy systems or from
  processes with many descriptors.

### Changed

- Extracted the listening-socket decode into a pure `decodeListenSocket`
  function and added unit tests covering IPv4, IPv6, and the
  non-TCP / non-listening / port-zero rejection cases. The scanner's core
  decoding is now testable without syscalls.

## 0.2.0 - 2026-06-01

### Added

- Watch mode with colored row states for new, removed, and unchanged listeners.
- Kill mode for terminating the process listening on a port, with confirmation and `--force` support.
- CI for macOS Zig 0.16 builds, tests, formatting, and smoke checks.
- Unit tests for CLI parsing, output formatting, JSON escaping, watch keys, and kill target selection.

### Changed

- Migrated the project to Zig 0.16.
- Refactored CLI parsing into a testable module.
- `--help` now writes to stdout.
- Homebrew release automation now validates release tags and copies the checked-in formula template into the tap.

### Fixed

- Watch mode now uses collision-safe `(port, pid)` keys.
- Watch mode now respects port filters and rejects `--json` instead of silently ignoring it.
- Kill mode no longer uses `waitpid` for arbitrary processes.
- Kill mode refuses ambiguous multiple-process matches instead of killing the first match.
- Kill mode verifies process absence before reporting success.
- JSON output now escapes control characters.
