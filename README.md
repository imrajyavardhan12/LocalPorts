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
localports --tree
localports --watch, -w [seconds]
localports --kill, -k <port> [--force]
localports --kill <port> --all [--force]
localports --kill <port> --pid <pid> [--force]
localports --kill-pid <pid> [--force]
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
./zig-out/bin/localports --tree
./zig-out/bin/localports -p 3000 --tree --verbose
./zig-out/bin/localports --watch
./zig-out/bin/localports --watch 1
./zig-out/bin/localports 3000 --watch
./zig-out/bin/localports --kill 3000
./zig-out/bin/localports --kill 3000 --force
./zig-out/bin/localports --kill 8000 --all
./zig-out/bin/localports --kill 8000 --pid 6524
./zig-out/bin/localports --kill-pid 6524
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
localports --kill 3000              # the sole listener on the port
localports --kill 3000 --force      # skip confirmation
localports --kill 8000 --all        # every process on the port
localports --kill 8000 --pid 6524   # one pid, only if it is on the port
localports --kill-pid 6524          # a process by explicit PID, any port
```

When a port has more than one listener, plain `--kill <port>` refuses to choose. Use `--all` to kill them all, or `--pid <pid>` to select one. `--kill-pid <pid>` targets a PID directly without a port lookup.

Safety behavior:

- If no process is found, exits with code `1`.
- If multiple processes are listening on the same port, plain `--kill <port>` refuses to choose one automatically, prints the matching rows, and exits with code `1`. Use `--all` or `--pid <pid>` to act intentionally.
- `--kill <port> --pid <pid>` exits with code `1` if that pid is not listening on the port.
- `--all` and `--pid` require `--kill <port>`; `--kill-pid` cannot be combined with `--kill`/`--all`/`--pid`. Invalid combinations exit with code `1`.
- With `--all`, every matching process is attempted; the command exits non-zero if any kill fails.
- If permission is denied, exits with code `1` and suggests `sudo`.
- If a confirmation prompt is declined, exits with code `2`.

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

## Process tree

`--tree` shows each listener's parent-process chain, so you can tell whether a port is held by your dev server's worker, a stray process from a crashed run, or something launched by Docker:

```bash
localports --tree
localports -p 3000 --tree --verbose
```

```text
PORT   PID    PROCESS  ADDRESS
3000   49729  node     127.0.0.1
              └─ npm (49687)
                └─ zsh (49600)
```

The chain runs from the immediate parent up toward `launchd` (pid 1), which is omitted. `--tree` composes with `--verbose`, and under `--json` it adds an `ancestors` array per row.

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

`--json --tree` adds an `ancestors` array per row (immediate parent first):

```json
{ "port": 3000, "pid": 49729, "proto": "tcp", "process": "node", "address": "127.0.0.1",
  "ancestors": [ { "pid": 49687, "name": "npm" }, { "pid": 49600, "name": "zsh" } ] }
```

## Example

```text
PORT   PID    PROCESS        ADDRESS
3000   12345  node           0.0.0.0
5432   67890  postgres       127.0.0.1
```
