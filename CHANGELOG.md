# Changelog

## Unreleased

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
