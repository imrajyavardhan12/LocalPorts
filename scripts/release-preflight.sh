#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: release-preflight.sh <vX.Y.Z>}"
signers_file="${RELEASE_SIGNERS_FILE:-.github/release-signers}"

if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag must be vX.Y.Z, got ${tag}" >&2
  exit 1
fi

if [[ "$(git cat-file -t "${tag}")" != "tag" ]]; then
  echo "error: ${tag} must be an annotated tag" >&2
  exit 1
fi

if [[ ! -f "${signers_file}" ]]; then
  echo "error: release signer allowlist is missing: ${signers_file}" >&2
  exit 1
fi

git -c "gpg.ssh.allowedSignersFile=${signers_file}" verify-tag "${tag}"

commit="$(git rev-list -n1 "${tag}")"
if ! git merge-base --is-ancestor "${commit}" origin/main; then
  echo "error: ${tag} (${commit}) is not reachable from origin/main" >&2
  exit 1
fi

version="${tag#v}"
zon_version="$(git show "${tag}:build.zig.zon" | sed -nE 's/^[[:space:]]*\.version = "([^"]+)".*/\1/p' | head -n1)"
src_version="$(git show "${tag}:src/version.zig" | sed -nE 's/^pub const version = "([^"]+)".*/\1/p' | head -n1)"
if [[ "${zon_version}" != "${version}" || "${src_version}" != "${version}" ]]; then
  echo "error: ${tag} version mismatch: build.zig.zon=${zon_version:-missing}, src/version.zig=${src_version:-missing}" >&2
  exit 1
fi

escaped_version="${version//./\\.}"
if ! git show "${tag}:CHANGELOG.md" | grep -Eq "^## ${escaped_version} - [0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
  echo "error: CHANGELOG.md is missing a dated ${version} heading" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "tag=${tag}"
    echo "version=${version}"
    echo "commit=${commit}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "release preflight passed: ${tag} (${commit})"
