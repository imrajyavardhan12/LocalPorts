# Changelog

## 0.2.0 - Unreleased

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
