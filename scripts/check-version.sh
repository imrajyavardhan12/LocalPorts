#!/usr/bin/env bash
set -euo pipefail

zon_version="$({ grep -E '^[[:space:]]*\.version = "' build.zig.zon || true; } | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"
src_version="$({ grep -E '^pub const version = "' src/version.zig || true; } | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"

if [[ -z "${zon_version}" ]]; then
  echo "error: could not read version from build.zig.zon" >&2
  exit 1
fi

if [[ -z "${src_version}" ]]; then
  echo "error: could not read version from src/version.zig" >&2
  exit 1
fi

if [[ "${zon_version}" != "${src_version}" ]]; then
  echo "error: version mismatch: build.zig.zon=${zon_version}, src/version.zig=${src_version}" >&2
  exit 1
fi

release_tag="${1:-${TAG:-}}"
if [[ -n "${release_tag}" && "${release_tag}" != "v${zon_version}" ]]; then
  echo "error: release tag ${release_tag} does not match project version v${zon_version}" >&2
  exit 1
fi

echo "version ok: ${zon_version}"
