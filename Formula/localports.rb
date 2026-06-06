class Localports < Formula
  desc "Fast local TCP port inspector for macOS"
  homepage "https://github.com/imrajyavardhan12/LocalPorts"
  # The release workflow copies this formula into the tap and replaces url/sha256.
  url "https://github.com/imrajyavardhan12/LocalPorts/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "14ecbff2c1e3796b69364d39f5acad89dffd478923698a3d5a062e7c6720ef2b"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/localports"
    man1.install "man/localports.1"
    bash_completion.install "completions/localports.bash" => "localports"
    zsh_completion.install "completions/_localports"
    fish_completion.install "completions/localports.fish"
  end

  test do
    system "#{bin}/localports", "--help"
    system "#{bin}/localports", "--version"
  end
end
