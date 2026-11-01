class Tidemark < Formula
  desc "Menu bar app that shows Claude plan usage limits"
  homepage "https://github.com/lcalmsky/tidemark"
  url "https://github.com/lcalmsky/tidemark/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "54b7c6e9a2864052cc2f3687665ff14d1a082f4e338a45af233d1516b10f089d"
  head "https://github.com/lcalmsky/tidemark.git", branch: "main"

  depends_on :macos

  def install
    ENV["SWIFT_BUILD_DISABLE_SANDBOX"] = "1"
    system "./scripts/bundle.sh", prefix
    bin.install_symlink prefix/"Tidemark.app/Contents/MacOS/tidemark"
  end

  service do
    run [opt_prefix/"Tidemark.app/Contents/MacOS/tidemark"]
    keep_alive successful_exit: false
  end

  test do
    assert_match "tidemark", shell_output("#{bin}/tidemark --version")
  end
end
