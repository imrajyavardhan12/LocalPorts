#!/usr/bin/env bash
set -euo pipefail

output="${1:?usage: render-homebrew-formula.sh <output> <arm-url> <arm-sha> <x64-url> <x64-sha>}"
arm_url="${2:?usage: render-homebrew-formula.sh <output> <arm-url> <arm-sha> <x64-url> <x64-sha>}"
arm_sha="${3:?usage: render-homebrew-formula.sh <output> <arm-url> <arm-sha> <x64-url> <x64-sha>}"
x64_url="${4:?usage: render-homebrew-formula.sh <output> <arm-url> <arm-sha> <x64-url> <x64-sha>}"
x64_sha="${5:?usage: render-homebrew-formula.sh <output> <arm-url> <arm-sha> <x64-url> <x64-sha>}"

mkdir -p "$(dirname "${output}")"
cp Formula/localports.rb "${output}"
sed -i.bak \
  -e "s|AARCH64_URL_PLACEHOLDER|${arm_url}|" \
  -e "s|AARCH64_SHA_PLACEHOLDER|${arm_sha}|" \
  -e "s|X86_64_URL_PLACEHOLDER|${x64_url}|" \
  -e "s|X86_64_SHA_PLACEHOLDER|${x64_sha}|" \
  "${output}"
rm -f "${output}.bak"

ruby -c "${output}"
if grep -q PLACEHOLDER "${output}"; then
  echo "error: unreplaced placeholder remains in ${output}" >&2
  exit 1
fi
grep -F "${arm_sha}" "${output}" >/dev/null
grep -F "${x64_sha}" "${output}" >/dev/null
