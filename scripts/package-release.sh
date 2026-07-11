#!/usr/bin/env bash
# Build self-contained macOS binaries and package each with its man page and
# shell completions into a release tarball under the output directory.
#
# Both targets are cross-compiled with Zig. The aarch64 binary is ad-hoc signed
# by Zig's Mach-O linker (required to run on Apple Silicon); the x86_64 binary
# needs no signature. A ReleaseFast localports links only /usr/lib/libSystem, so
# the Homebrew formula installs these with no runtime dependencies and never
# pulls in the zig/LLVM toolchain on a user's machine.
set -euo pipefail

out_dir="${1:-dist}"
mkdir -p "$out_dir"
rm -f "$out_dir"/localports-*-macos.tar.gz

# Zig target triples; the arch label is derived by stripping "-macos".
# Release CI sets LOCALPORTS_RELEASE_TARGETS to package only the runner-native
# architecture. Local packaging retains both targets by default.
read -r -a targets <<< "${LOCALPORTS_RELEASE_TARGETS:-aarch64-macos x86_64-macos}"

for ztarget in "${targets[@]}"; do
  arch="${ztarget%-macos}"
  stage="$(mktemp -d)"

  zig build -Dtarget="$ztarget" -Doptimize=ReleaseFast --prefix "$stage/zig"

  pkg="$stage/pkg"
  mkdir -p "$pkg"
  cp "$stage/zig/bin/localports" "$pkg/localports"
  cp man/localports.1 "$pkg/localports.1"
  cp completions/localports.bash "$pkg/localports.bash"
  cp completions/_localports "$pkg/_localports"
  cp completions/localports.fish "$pkg/localports.fish"

  tar -czf "$out_dir/localports-${arch}-macos.tar.gz" -C "$pkg" \
    localports localports.1 localports.bash _localports localports.fish

  rm -rf "$stage"
done

echo "packaged into ${out_dir}/:"
ls -1 "$out_dir"/localports-*-macos.tar.gz