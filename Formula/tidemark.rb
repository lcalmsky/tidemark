class Tidemark < Formula
  desc "Menu bar app that shows Claude plan usage limits"
  homepage "https://github.com/lcalmsky/tidemark"
  url "https://github.com/lcalmsky/tidemark/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "675d492afae17686ec8f393f792f7a2fe3649f3661dec2859a6e077d38cc18f7"
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
