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
      sha256 "8ca58073746fe3f5b8b5cdaf34db084cfeb0ba7d91b83043eb8ce0ba620aadca"
    end
    on_intel do
      url "#{base_url}/zellij-osc-9-777-macos-x86_64-intel.tar.gz"
      sha256 "d95670f8521de89a069451f4e79b438db838c1812c1123025864fa1507ba4282"
    end
  end

  on_linux do
    url "#{base_url}/zellij-osc-9-777-linux-x86_64-musl.tar.gz"
    sha256 "e8e402a2332a0106447838aae2665822ff05f260dbd37d5c2cd527d292feb9e2"
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
