<p align="center">
  <img src="assets/port.png" alt="localports" width="120">
</p>

<h1 align="center">localports</h1>

<p align="center">A fast macOS CLI to see what's on a port, understand <em>why</em>, and safely free it.</p>

<p align="center">
  <a href="https://github.com/imrajyavardhan12/LocalPorts/actions/workflows/ci.yml"><img src="https://github.com/imrajyavardhan12/LocalPorts/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey" alt="Platform: macOS">
  <img src="https://img.shields.io/badge/Zig-0.16-F7A41D?logo=zig&logoColor=white" alt="Built with Zig">
</p>

<p align="center">
  <img src="assets/demo.gif" alt="localports demo" width="820">
</p>

Inspect local TCP ports: see what's listening, understand **why** (owning user, full command, process ancestry, Docker container), and safely free a port when you need it. One small binary, no background daemon, typically answers in a few milliseconds.

## Features

- **Fast** — a single binary, ~3–5 ms warm scans on Apple Silicon, no daemon and no persistent state.
- **Context** — owning user and full command line (`--verbose`), and each listener's parent-process chain (`--tree`).
- **Docker-aware** — resolves a container-published port (owned by `com.docker.backend`) to the actual container name, image, and container-side port (`--docker`).
- **Safe termination** — confirmation by default, refusal on ambiguous ports, and explicit `--all` / `--pid` / `--kill-pid` controls for intentional kills.
- **Live watch** — color-coded refresh of listeners as they appear and disappear (`--watch`).
- **Scriptable** — a stable default JSON contract; extra fields appear only behind their flag, so scripts keep working.

## Install

### Homebrew

```bash
brew tap imrajyavardhan12/localports
brew install localports
```

### Build from source

Requires [Zig](https://ziglang.org) 0.16.x.

```bash
zig build -Doptimize=ReleaseFast
# binary at ./zig-out/bin/localports
```

## Quick start

```bash
localports                 # list all listening TCP ports
localports 3000            # just port 3000
localports --verbose       # add owning user + full command
localports --tree          # add the parent-process chain
localports --docker        # resolve Docker ports to their container
localports --kill 3000     # safely free a port
```

Run with `sudo` to see processes owned by other users:

```bash
sudo localports
```

## Usage

```text
localports [options] [port]
```

| Option | Description |
| --- | --- |
| `-p, --port <port>` | Filter by port number (also accepted as a bare positional argument) |
| `--json` | Machine-readable JSON output |
| `--verbose` | Show the owning user and full command line (scan only) |
| `--tree` | Show each listener's parent-process chain (scan only) |
| `--docker` | Resolve Docker-owned ports to their container (scan only) |
| `-w, --watch [secs]` | Live refresh, default every 2 seconds |
| `-k, --kill <port>` | Kill the process on a port (refuses ambiguous matches) |
| `-a, --all` | With `--kill <port>`: kill every matching process |
| `--pid <pid>` | With `--kill <port>`: kill only that pid if it is on the port |
| `--kill-pid <pid>` | Kill a process by explicit PID |
| `-f, --force` | Skip the kill confirmation prompt |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

The display flags (`--verbose`, `--tree`, `--docker`) compose with each other and apply to one-shot scans.

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

## Docker

On macOS, a port published by a container shows up owned by `com.docker.backend`, which tells you nothing about *which* container. `--docker` resolves it:

```bash
localports --docker
localports -p 5432 --docker
```

```text
PORT   PID    PROCESS             ADDRESS    CONTAINER
5432   9743   com.docker.backend  127.0.0.1  pg-dev (postgres:16-alpine ->5432)
3000   123    node                127.0.0.1  -
```

It runs `docker ps` once (only when a Docker-owned port is present) to map host port → container name, image, and container-side port. Non-Docker rows show `-`. If `docker` isn't installed or the daemon is down, the column stays `-` rather than erroring. Under `--json` it adds a `container` object (or `null`) per row.

## Watch mode

Watch mode refreshes immediately, then every N seconds, respecting the same port filter as one-shot scans:

```bash
localports --watch        # refresh every 2 seconds
localports --watch 1      # refresh every 1 second
localports 3000 --watch   # watch only port 3000
```

Watch mode is table-only; `--json --watch` is rejected. Rows are color-coded:

- **Green** — newly appeared listener
- **Red** — listener that disappeared since the previous refresh
- Default — unchanged listener

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
- If a port-based kill would target a Docker host process, it refuses so you don't accidentally kill Docker Desktop instead of the container publishing the port. Use `localports <port> --docker` or `docker ps`, then stop the container intentionally.
- `--kill <port> --pid <pid>` exits with code `1` if that pid is not listening on the port.
- `--all` and `--pid` require `--kill <port>`; `--kill-pid` cannot be combined with `--kill` / `--all` / `--pid`. Invalid combinations exit with code `1`.
- With `--all`, every matching process is attempted; the command exits non-zero if any kill fails. A process that has already exited counts as success.
- If permission is denied, exits with code `1` and suggests `sudo`.
- If a confirmation prompt is declined, exits with code `2`.

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

`--json --docker` adds a `container` object (or `null`) per row:

```json
{ "port": 5432, "pid": 9743, "proto": "tcp", "process": "com.docker.backend", "address": "127.0.0.1",
  "container": { "name": "pg-dev", "image": "postgres:16-alpine", "container_port": 5432 } }
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Error — port not found, ambiguous kill refused, permission denied, invalid flag combination, or a kill that failed |
| `2` | A kill confirmation prompt was declined |

## Performance

Typical warm runs complete in ~3–5 ms on Apple Silicon. The first run may be slower while the relevant pages are warmed in cache. The scanner uses macOS `libproc` directly (no shelling out), and the `--docker` lookup is the only path that spawns a subprocess — and only when a Docker-owned port is present.

## Platform support

macOS only today (Apple Silicon and Intel). The codebase dispatches on the target OS and a Linux `/proc` backend is planned; until then, non-macOS builds are not supported.

## Development

```bash
zig build -Doptimize=ReleaseFast   # build
zig build test                     # run the test suite
zig fmt --check build.zig build.zig.zon src/*.zig   # formatting
```

Continuous integration builds, tests, format-checks, and smoke-tests the CLI on macOS with Zig 0.16.

## License

[MIT](LICENSE)
