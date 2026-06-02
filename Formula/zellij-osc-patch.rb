class ZellijOscPatch < Formula
  desc "Patched zellij with OSC 9 / OSC 777 desktop notification passthrough"
  homepage "https://github.com/Caojianfa/zellij-fork"
  version "0.45.0-osc-9-777"
  license "MIT"

  # Same release tarballs that live alongside this formula in
  # releases/ on the feature branch. SHA256SUMS in that directory is
  # the source of truth for these hashes.
  base_url = "https://github.com/Caojianfa/zellij-fork/raw/claude/osc-notification-passthrough-WMI63/releases"

  on_macos do
    on_arm do
      url "#{base_url}/zellij-osc-9-777-macos-aarch64-apple-silicon.tar.gz"
      sha256 "a8cda70a070d011f381bf9f4d16a181226b02a988b7a92f42488d28f06557dc4"
    end
    on_intel do
      url "#{base_url}/zellij-osc-9-777-macos-x86_64-intel.tar.gz"
      sha256 "3b9e855416a501f49e4edc36e2a27f1527dde4827e76eda62f5ac14301cd9796"
    end
  end

  on_linux do
    url "#{base_url}/zellij-osc-9-777-linux-x86_64-musl.tar.gz"
    sha256 "dc892edf13f8068acbe7d03ae63fa280937cd13c5bd76ecede09bc11ef6c39be"
  end

  def install
    # The tarball contains a single binary file; rename to `zellij`
    # and place into Homebrew's bin/.
    Dir.glob("zellij-osc-9-777-*").each do |bin_path|
      bin.install bin_path => "zellij"
    end
  end

  test do
    assert_match "zellij 0.45.0", shell_output("#{bin}/zellij --version")
    # Verify the new --allow-osc-passthrough flag is exposed by the patch.
    assert_match "allow-osc-passthrough",
      shell_output("#{bin}/zellij options --help 2>&1")
  end
end
