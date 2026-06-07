#!/usr/bin/env bash
set -euo pipefail

long_flags=(
  --port
  --json
  --watch
  --kill
  --all
  --pid
  --kill-pid
  --force
  --verbose
  --tree
  --docker
  --version
  --help
)

check() {
  local file="$1"
  local pattern="$2"
  if ! grep -F -- "$pattern" "$file" >/dev/null; then
    echo "error: ${file} is missing ${pattern}" >&2
    exit 1
  fi
}

for flag in "${long_flags[@]}"; do
  name="${flag#--}"
  check src/main.zig "$flag"
  check completions/_localports "$flag"
  check completions/localports.bash "$flag"
  check completions/localports.fish "-l ${name}"
  check man/localports.1 "Fl -${name}"
done

# Keep short-option assets in sync too. Not every command has a short form.
short_flags=(
  p:port
  w:watch
  k:kill
  a:all
  f:force
  v:version
  h:help
)

for spec in "${short_flags[@]}"; do
  short="${spec%%:*}"
  long="${spec##*:}"
  check completions/_localports "-${short},--${long}"
  check completions/localports.bash " -${short}"
  check completions/localports.fish "-s ${short}"
  check man/localports.1 "Fl ${short}"
done

echo "cli assets ok"
