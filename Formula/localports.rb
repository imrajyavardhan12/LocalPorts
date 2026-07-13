class Localports < Formula
  desc "Fast local TCP port inspector for macOS"
  homepage "https://github.com/imrajyavardhan12/LocalPorts"
  license "MIT"

  # The release workflow cross-compiles the binaries, uploads them as release
  # assets, and replaces the version/url/sha256 placeholders below. A localports
  # binary links only /usr/lib/libSystem, so there are no runtime dependencies
  # and no build toolchain (zig/LLVM) is installed on the user's machine.
  on_macos do
    on_arm do
      url "AARCH64_URL_PLACEHOLDER"
      sha256 "AARCH64_SHA_PLACEHOLDER"
    end
    on_intel do
      url "X86_64_URL_PLACEHOLDER"
      sha256 "X86_64_SHA_PLACEHOLDER"
    end
  end

  def install
    bin.install "localports"
    man1.install "localports.1"
    bash_completion.install "localports.bash" => "localports"
    zsh_completion.install "_localports"
    fish_completion.install "localports.fish"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/localports --version")
  end
end
