class Tidemark < Formula
  desc "Menu bar app that shows Claude plan usage limits"
  homepage "https://github.com/lcalmsky/tidemark"
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
