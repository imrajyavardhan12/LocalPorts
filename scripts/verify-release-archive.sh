#!/usr/bin/env bash
set -euo pipefail

archive="${1:?usage: verify-release-archive.sh <archive> <aarch64-macos|x86_64-macos>}"
target="${2:?usage: verify-release-archive.sh <archive> <aarch64-macos|x86_64-macos>}"

case "${target}" in
  aarch64-macos) expected_arch="arm64" ;;
  x86_64-macos) expected_arch="x86_64" ;;
  *)
    echo "error: unsupported target: ${target}" >&2
    exit 1
    ;;
esac

expected_entries=$'_localports\nlocalports\nlocalports.1\nlocalports.bash\nlocalports.fish'
actual_entries="$(tar -tzf "${archive}" | sed 's#^\./##' | sort)"
if [[ "${actual_entries}" != "${expected_entries}" ]]; then
  echo "error: ${archive} has unexpected contents:" >&2
  printf '%s\n' "${actual_entries}" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
tar -xzf "${archive}" -C "${tmp}"

if ! file "${tmp}/localports" | grep -F "${expected_arch}" >/dev/null; then
  echo "error: ${archive} does not contain a ${expected_arch} executable" >&2
  exit 1
fi

current_arch="$(uname -m)"
if [[ ("${target}" == "aarch64-macos" && "${current_arch}" == "arm64") ||
      ("${target}" == "x86_64-macos" && "${current_arch}" == "x86_64") ]]; then
  "${tmp}/localports" --version | grep '^localports '
  "${tmp}/localports" --help >/dev/null
fi
