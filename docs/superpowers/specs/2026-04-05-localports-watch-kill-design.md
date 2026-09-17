# localports Watch Mode + Kill Feature Design

## Overview

Add two high-utility developer features: continuous port monitoring (watch mode) and process termination (kill).

---

## Watch Mode

### CLI Interface

```
localports --watch [seconds]
localports -w [seconds]
```

- Flag `--watch` or `-w` enables watch mode
- Optional integer argument sets refresh interval in seconds (default: 2)
- `localports --watch 1` refreshes every 1 second
- `localports --watch` (no argument) defaults to 2 seconds
- Ctrl+C exits cleanly

### Interactive Terminal UI

- Clear terminal screen on each refresh (using ANSI escape `ESC[2J`)
- Show header row on every refresh
- Row color coding:
  - **Green**: newly appeared port since last refresh
  - **Red**: port that disappeared since last refresh
  - **Default**: port unchanged from last refresh
- Track state changes by (port, pid) tuple
- Table re-sorted by port on each refresh

### Output Format

Watch mode is table-only (not JSON). JSON doesn't make sense for continuous output.

### Behavior

- Initial scan runs immediately (not delayed by interval)
- Subsequent scans run every N seconds
- Display message if no changes between refreshes: "No changes detected."
- On first run of watch mode, all rows shown as "new"

---

## Kill Functionality

### CLI Interface

```
localports --kill <port>
localports -k <port>
```

- Requires port argument
- Exits immediately after kill attempt (not combined with watch)

### Process Termination

1. Look up the process listening on the specified port
2. Show confirmation prompt: `Kill process <name> (PID <pid>) on port <port>? [y/N]`
3. On user confirmation:
   - Send SIGTERM to the process
   - Wait up to 5 seconds for process to exit
   - If still running after 5s, send SIGKILL
4. Exit codes:
   - 0: process killed successfully
   - 1: port not found / no process listening
   - 2: user declined confirmation

### Force Flag

```
localports --kill <port> --force
localports -k <port> -f
```

- Skips confirmation prompt
- Useful for scripts

### Error Cases

- Port not found in scan → exit code 1, message "No process found listening on port <port>"
- Multiple processes on same port (rare) → kill the first one found, warn user
- Permission denied → exit code 1, message "Permission denied. Try running with sudo."

---

## Combined Behavior

- `--watch` and `--kill` are mutually exclusive
- If both specified, `--kill` takes precedence and runs immediately
- `--kill` output: brief confirmation of kill or error, then exits

---

## Architecture

### Changes to `src/main.zig`

- Add watch mode loop after initial scan
- Add kill command handler before/after scan logic
- Pass state between refresh iterations for diff detection

### Changes to `src/darwin.zig`

- No changes needed for kill — use `std.os.kill` via Zig's standard library

### New state tracking

- Maintain previous scan results in a map keyed by `{port, pid}`
- On each refresh, diff against previous to classify rows

### ANSI Terminal Colors

- Use `ESC[32m` for green (new)
- Use `ESC[31m` for red (removed)
- Use `ESC[0m` to reset

---

## Files to Modify

- `src/main.zig` — CLI parsing, watch loop, kill flow
- `src/darwin.zig` — (no changes expected)
- `src/linux.zig` — (no changes expected)
- `src/output.zig` — add colored table output variant

---

## Testing

- Manual test: run watch mode, start/kill a process, observe color changes
- Test kill with a known port (e.g., start a server on port 9999, kill it)
- Test error cases: kill non-existent port, kill without permission
