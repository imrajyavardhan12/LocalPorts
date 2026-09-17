# Handoff — Next Session

Date: 2026-07-10
Project: `localports`

## Current state

`v0.7.0` is released and live on Homebrew. `main` starts at `0309348`.

v0.8.0 trust and correctness is implemented locally and awaiting final review:

- Darwin scanning preserves distinct IPv4, IPv6, interface, and scoped
  endpoints while collapsing exact duplicate descriptors.
- Watch identity includes the endpoint address.
- Port-based kills deduplicate rows by PID and signal each process once.
- Docker mapping is address-aware and leaves conflicting mappings unresolved.
- Interactive scans aggregate partial-visibility diagnostics; JSON stays clean,
  and confirmed scan truncation makes kill fail closed.
- CI has a comparative ReleaseFast performance gate with an automatic rerun.
- Regression coverage includes real dual-stack listeners, duplicate
  descriptors, exposure filtering, watch transitions, kill target selection,
  Docker conflicts, scoped IPv6, and the stable JSON schema.

Do not redo README or demo work unless asked.

## Repo / local-only state

Before v0.8.0 work, the intentionally local-only files were:

```bash
git status --short
# ?? CLAUDE.md
# ?? docs/
```

`docs/` (ROADMAP, this handoff, superpowers spec) and `CLAUDE.md` are **not
pushed** by design. Don't push them unless the user explicitly asks.

The current working tree also contains the v0.8.0 implementation and test
changes described above.

## Product direction (updated 2026-07-10)

Goal locked with the user: **the best port tool for a Mac developer's daily
workflow**, giving the fastest, clearest answer to "what owns this port, why,
and what can I safely do about it." Optimize **depth + ergonomics on macOS over
breadth.** `docs/ROADMAP.md` is the source of truth.

Consequence: the **Linux backend is deprioritized** (it was v0.4.0 in the old
roadmap). It's low personal/team value for a macOS daily driver — only
resurface it if the user's team standardizes on Linux hosts.

## Recommended next-session goal

Review the v0.8.0 diff, run the full validation matrix, then prepare the
release. Do not add unrelated features before this correctness milestone ships.

## Architecture notes worth carrying

- **Listener identity is endpoint-level.** `types.ListenerKey` includes PID,
  port, family, local address, and IPv6 scope. Scanner and watch code share the
  same comparator and key. Kill code deliberately reduces endpoint rows back to
  unique process targets.
- **`src/docker.zig`** is cross-platform: `isDockerProcess` (name check),
  `parsePsOutput` (pure, unit-tested — borrows the input text), `lookup`, and
  `enrich` (runs `docker ps` via `std.process.run`, only when a Docker-owned
  port is present). Endpoint lookup prefers an exact address and port and
  returns null rather than guessing across conflicting containers.
- **`output.writeTable` is a column model** now (`Column` enum +
  `columnHeader`/`columnCell`). `COMMAND` is always the last column (it can be
  long, so it's never measured/padded); `CONTAINER` sits before it. Adding a
  display column = add to the enum + the assembly list. Existing output is
  byte-identical for non-flag modes — guarded by the table/JSON tests.
- **Display-flag pattern** (follow it for new display features): `--verbose` /
  `--tree` / `--docker` are opt-in, arena-backed enrichment that
  leave the **default table and JSON contract unchanged**; JSON fields appear
  only under the flag. They work in one-shot scans and watch mode. Enrichment
  data is shared by PID when one process owns multiple endpoints.
- **`types.zig`**: `PortEntry` carries optional `user` / `command` / `ancestors`
  / `container`, endpoint scope, and scan diagnostics; plus `Ancestor` and
  `Container` types.
- **Partial visibility is explicit.** `darwin.scanReporting` retries saturated
  libproc buffers and returns aggregate diagnostics. Interactive table output
  warns once, JSON remains unchanged, and kill refuses confirmed truncation.
- Platform dispatch is still `builtin.os.tag` in `main.zig`; `linux.zig` is a
  `@compileError` stub (so non-macOS builds fail by design).

## Conventions & constraints (important — carry forward)

- **Commits/PRs carry NO attribution**: no `Co-Authored-By` trailer and no
  "Generated with Claude Code" footer. The user asked for both to be removed
  (see memory `no-claude-code-footer`). Write PR/commit bodies with
  `--body-file` / `-F` (not heredocs) so the `EOF` delimiter can't leak.
- **Workflow**: branch off `main` → small TDD vertical slices → `/code-review`
  before merge (run inline; don't fan out cloud agents unless asked) →
  squash-merge with a clean message → delete branch. The user has been happy
  for the agent to drive this and to run the tag + release.
- **Release process**: bump `src/version.zig` **and** `build.zig.zon` together,
  rename CHANGELOG `## Unreleased` → `## X.Y.Z - <date>`, commit
  `Prepare vX.Y.Z release` → PR → merge → `git tag -a vX.Y.Z` +
  `gh release create` (fires `update-homebrew.yml`). `scripts/check-version.sh`
  validates the tag matches the project version. Bump versions only at
  release-prep time, never per feature PR.
- **Safety invariants**: never weaken kill ambiguity refusal; keep the default
  JSON contract stable; never claim Linux support before it exists.

## Product ideas already evaluated and DECLINED (don't relitigate)

The user floated three ambitious features; all were declined as wrong for this
tool because each turns a stateless, instant, safe CLI into an always-running
system, which is the opposite of what makes it good:

1. **Forensics / replay "time machine"** — needs a 24/7 poller (macOS has no
   LISTEN event source → lossy + battery), logs env vars (secrets), and
   "replay" is unreliable. *Only* salvageable kernel: a tiny stateless
   kill-history (log the user's own kills to a file, no daemon) — optional.
2. **Port bonding / transparent failover** — a proxy in the data path;
   `SO_REUSEPORT` can't drain existing connections, injection is SIP-blocked,
   and local zero-downtime barely matters. Hard pass.
3. **Policy engine / "bouncer"** — a daemon that autonomously kills processes;
   inverts the careful kill-safety model, can't actually *block* (only kill
   reactively), and needs continuous polling + a rule engine. Hard pass.

Principle to keep: **localports is a tool, not a system.** Stay on the
depth + ergonomics track.

## Validation commands

```bash
zig fmt --check build.zig build.zig.zon src/*.zig
zig build test
zig build -Doptimize=ReleaseFast
bash scripts/check-version.sh        # add a vX.Y.Z arg to also check the tag
python3 -m py_compile scripts/check-performance.py
./zig-out/bin/localports --json | python3 -m json.tool
```

For a performance comparison, build `HEAD` and the candidate with
`-Doptimize=ReleaseFast`, then pass both binaries to
`scripts/check-performance.py`. CI does this automatically for pull requests.

## E2E patterns

- Disposable listeners on `127.0.0.1`: `python3 -m http.server <port>` or
  `nc -l <port>` (short command, nice for `--verbose` shots).
- Two listeners on one port (for ambiguity / `--all` / `--pid`): bind with
  `SO_REUSEPORT` (a tiny Python snippet) — plain servers refuse the second bind.
- `--docker`: throwaway containers (`nginx:alpine`, `postgres:16-alpine`) with
  `-p host:ctr`, scan, then `docker rm -f`.
- Bash gotcha hit this session: a backgrounded process inside `$(...)` blocks
  command substitution until its stdout closes — redirect the child's fds
  (`>/dev/null 2>&1 &`).

## Reference docs

- Roadmap (with current direction): `docs/ROADMAP.md`
- Watch/kill design spec: `docs/superpowers/specs/2026-04-05-localports-watch-kill-design.md`
- Release notes: `CHANGELOG.md`
- Build/architecture guidance: `CLAUDE.md`
