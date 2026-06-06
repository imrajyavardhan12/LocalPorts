# Changelog

## Unreleased

### Changed

- Optimized macOS scanner deduplication from a linear scan over collected
  entries to a hash-set lookup while preserving the existing `(port, pid)`
  behavior.

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
