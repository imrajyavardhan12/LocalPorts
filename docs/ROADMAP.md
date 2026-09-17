# Roadmap

## Direction (updated 2026-07-10)

Product goal: **the best port tool for a Mac developer's daily workflow** —
fastest, clearest answer to "what owns this port, why, and what can I safely
do about it." Optimize for depth and ergonomics on macOS over breadth.

Current sequence:

- **Released:** v0.3.0 through v0.7.0 delivered scanner hardening, safe kill
  controls, verbose/tree/Docker context, CLI ergonomics, exposure awareness,
  canonical IPv6, TTY-gated color, and terminal-width truncation.
- **In progress:** v0.8.0 trust and correctness. Preserve every distinct bind
  endpoint, make watch identity address-aware, keep kill actions process-based,
  improve Docker mapping precision, surface incomplete scans safely, and guard
  scanner performance.
- **Deprioritized:** Linux. Resurface only when real usage justifies reducing
  macOS depth to fund a second backend.

The version sections below are the original plan, kept for reference.

## v0.8.0 - Trust and Correctness

Goal: make every displayed row and every destructive action trustworthy under
dual-stack, multi-address, high-churn, and permission-limited conditions.

- Listener identity is `(pid, port, address family, local address, IPv6 scope)`.
  Exact duplicate descriptors collapse, but IPv4/IPv6 and distinct bind
  addresses remain visible as separate rows.
- Watch mode uses the same endpoint identity, so an address change appears as
  one removed row and one new row.
- Kill resolution deduplicates scanner rows by PID, so a process is prompted
  for and signalled at most once.
- Docker lookup prefers an exact host address and port, and refuses to guess
  when same-port mappings conflict.
- Interactive table scans aggregate incomplete-scan diagnostics into one
  warning. JSON remains clean, and confirmed truncation makes kill fail closed.
- Pull requests compare ReleaseFast scan latency against their base revision,
  with one automatic rerun before reporting a regression.

Release criteria:

- Distinct listener endpoints appear exactly once.
- A network bind cannot be hidden by a loopback sibling.
- Default JSON keys and types remain unchanged.
- Full tests, build, CLI asset checks, smoke tests, packaging, and performance
  checks pass.

## v0.3.0 — Safe Control Release

Goal: make `localports` not just a fast inspector, but a safe tool for acting on port conflicts.

### 1. Better kill UX

Target commands:

```bash
localports --kill 8000 --all
localports --kill 8000 --pid 6524
localports --kill-pid 6524
```

Expected behavior:

- If exactly one process matches a port, current `--kill <port>` flow still works.
- If multiple processes match a port, default behavior still refuses to choose automatically.
- `--all` kills all processes matching the selected port.
- `--pid <pid>` kills only that PID if it is one of the processes matching the selected port.
- `--kill-pid <pid>` kills by explicit PID.
- Confirmation is required unless `--force` is present.

Rationale: preserve the safety added in v0.2.0 while giving users an intentional escape hatch.

### 2. Verbose output

Target commands:

```bash
localports --verbose
localports -p 8000 --verbose
localports --json --verbose
```

Potential table shape:

```text
PORT   PID    PROCESS  ADDRESS    USER   COMMAND
8000   6524   Python   127.0.0.1  rvs    python3 -m http.server 8000
```

Potential extra JSON fields under `--json --verbose`:

```json
{
  "port": 8000,
  "pid": 6524,
  "proto": "tcp",
  "process": "Python",
  "address": "127.0.0.1",
  "user": "rvs",
  "command": "python3 -m http.server 8000"
}
```

Default JSON should remain stable for scripts.

### 3. macOS scanner hardening

Improve reliability of the Darwin backend:

- Replace fixed PID buffer with dynamic sizing.
- Replace fixed FD buffer with dynamic sizing.
- Replace O(n²) dedup with a hash map.
- Revisit IPv4/IPv6 dedup behavior and decide whether address-level rows should be preserved.

### 4. JSON contract v1

Document the default JSON shape as stable:

```json
{
  "port": 8000,
  "pid": 6524,
  "proto": "tcp",
  "process": "Python",
  "address": "127.0.0.1"
}
```

Add new fields only behind explicit flags, such as `--verbose`, to avoid breaking scripts.

## v0.4.0 — Linux Backend

Implement Linux support using `/proc`:

- Parse `/proc/net/tcp` and `/proc/net/tcp6`.
- Map socket inode to PID via `/proc/<pid>/fd`.
- Match macOS output semantics where practical.
- Add Linux CI coverage.

## v0.5.0 — CLI Polish

- Add man page.
- Add shell completions:
  - zsh
  - bash
  - fish
- Install completions/man page via Homebrew formula.

## v1.0.0 — Stability Release

Release criteria:

- macOS backend is hardened.
- Linux backend is usable.
- JSON contract is documented and tested.
- Homebrew install path is reliable.
- Core commands have regression tests and manual E2E coverage.
