# localports

Fast local TCP port inspector for macOS, written in Zig. Shows which processes are listening and where.

## Performance

Typical warm runs complete in ~3–5ms on Apple Silicon. First run may be slower due to disk cache.

## Requirements

- Zig 0.16.x
- macOS (Linux backend planned)

## Build

```bash
zig build -Doptimize=ReleaseFast
```

The binary is output to `./zig-out/bin/localports`.

Run tests:

```bash
zig build test
```

## Install (Homebrew)

```bash
brew tap imrajyavardhan12/localports
brew install localports
```

## Usage

```bash
localports [port]
localports --port, -p <port>
localports --json
localports --verbose
localports --watch, -w [seconds]
localports --kill, -k <port> [--force]
localports --help, -h
localports --version, -v
```

Examples:

```bash
./zig-out/bin/localports
./zig-out/bin/localports 3000
./zig-out/bin/localports --port 3000
./zig-out/bin/localports --json
./zig-out/bin/localports --verbose
./zig-out/bin/localports -p 3000 --verbose
./zig-out/bin/localports --json --verbose
./zig-out/bin/localports --watch
./zig-out/bin/localports --watch 1
./zig-out/bin/localports 3000 --watch
./zig-out/bin/localports --kill 3000
./zig-out/bin/localports --kill 3000 --force
```

Run with `sudo` to see all system processes:

```bash
sudo ./zig-out/bin/localports
```

## Watch mode

Watch mode refreshes immediately, then every N seconds. It respects the same port filter as one-shot scans:

```bash
localports --watch        # refresh every 2 seconds
localports --watch 1      # refresh every 1 second
localports 3000 --watch   # watch only port 3000
```

Watch mode is table-only; `--json --watch` is rejected.

Rows are color-coded:

- Green: newly appeared listener
- Red: listener that disappeared since the previous refresh
- Default: unchanged listener

## Kill mode

Kill mode finds the process listening on a port, asks for confirmation, sends `SIGTERM`, waits up to 5 seconds, then escalates to `SIGKILL` if the process is still alive.

```bash
localports --kill 3000
localports --kill 3000 --force
```

Safety behavior:

- If no process is found, exits with code `1`.
- If multiple processes are listening on the same port, `localports` refuses to choose one automatically, prints the matching rows, and exits with code `1`.
- If permission is denied, exits with code `1` and suggests `sudo`.
- If the confirmation prompt is declined, exits with code `2`.

## Verbose mode

`--verbose` adds the owning user and the full command line for each listener, so you can tell *which* `node` or `python` is holding a port:

```bash
localports --verbose
localports -p 3000 --verbose
localports --json --verbose
```

```text
PORT   PID    PROCESS  ADDRESS    USER  COMMAND
8000   14682  Python   127.0.0.1  rvs   python3 -m http.server 8000 --bind 127.0.0.1
```

The command line and (occasionally) the user come from per-process lookups that require ownership. For processes owned by other users, run with `sudo` to see the full command; otherwise those fields show `-`.

## JSON output

The default `--json` shape is a stable contract. Each row always has these fields, and new fields are only added behind explicit flags so existing scripts keep working:

```json
{ "port": 8000, "pid": 6524, "proto": "tcp", "process": "Python", "address": "127.0.0.1" }
```

`--json --verbose` adds two more fields per row. When a value is unavailable they are emitted as empty strings:

```json
{ "port": 8000, "pid": 6524, "proto": "tcp", "process": "Python", "address": "127.0.0.1",
  "user": "rvs", "command": "python3 -m http.server 8000 --bind 127.0.0.1" }
```

## Example

```text
PORT   PID    PROCESS        ADDRESS
3000   12345  node           0.0.0.0
5432   67890  postgres       127.0.0.1
```
