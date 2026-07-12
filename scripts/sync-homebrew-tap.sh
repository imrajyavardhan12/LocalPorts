#!/usr/bin/env bash
set -euo pipefail

tap_dir="${1:?usage: sync-homebrew-tap.sh <tap-dir> <tag> <arm-sha> <x64-sha>}"
tag="${2:?usage: sync-homebrew-tap.sh <tap-dir> <tag> <arm-sha> <x64-sha>}"
arm_sha="${3:?usage: sync-homebrew-tap.sh <tap-dir> <tag> <arm-sha> <x64-sha>}"
x64_sha="${4:?usage: sync-homebrew-tap.sh <tap-dir> <tag> <arm-sha> <x64-sha>}"

version="${tag#v}"
base_url="https://github.com/imrajyavardhan12/LocalPorts/releases/download/${tag}"
formula="${tap_dir}/Formula/localports.rb"

current_version="$(ruby -ne 'puts Regexp.last_match(1) if /^\s*version "([^"]+)"/' "${formula}")"
if [[ -n "${current_version}" ]]; then
  if ruby -rrubygems -e 'exit(Gem::Version.new(ARGV[0]) > Gem::Version.new(ARGV[1]) ? 0 : 1)' "${current_version}" "${version}"; then
    echo "error: refusing to downgrade Homebrew formula from ${current_version} to ${version}" >&2
    exit 1
  fi
fi

bash scripts/render-homebrew-formula.sh \
  "${formula}" \
  "${version}" \
  "${base_url}/localports-aarch64-macos.tar.gz" \
  "${arm_sha}" \
  "${base_url}/localports-x86_64-macos.tar.gz" \
  "${x64_sha}"

brew style --strict "${formula}"
brew audit --strict --formula "${formula}"
brew install --formula "${formula}"
brew test "${formula}"

if git -C "${tap_dir}" diff --quiet -- Formula/localports.rb; then
  exit 0
fi

git -C "${tap_dir}" config user.name "github-actions[bot]"
git -C "${tap_dir}" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "${tap_dir}" add Formula/localports.rb
git -C "${tap_dir}" commit -m "Update localports formula to ${tag}"
git -C "${tap_dir}" push
