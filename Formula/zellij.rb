class Zellij < Formula
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
      sha256 "14b7ec4a0eff3baaa20ec10b9231f0b0a9b5afc245e85fbaf24dca05fa6e0d2e"
    end
    on_intel do
      url "#{base_url}/zellij-osc-9-777-macos-x86_64-intel.tar.gz"
      sha256 "1a084d13553b9bf9dbea7905a21c176150d73c80d9de3fb7dc076aff78e63c60"
    end
  end

  on_linux do
    url "#{base_url}/zellij-osc-9-777-linux-x86_64-musl.tar.gz"
    sha256 "22cf1275a7952754cde1c5b469f8a6773839fd028807013d361e53067efd609c"
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
