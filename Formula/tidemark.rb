class Tidemark < Formula
  desc "Menu bar app that shows Claude plan usage limits"
  homepage "https://github.com/lcalmsky/tidemark"
  url "https://github.com/lcalmsky/tidemark/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "d0439a4a743ff9ec4fe18daf603f367278266a7eee86798e876ef6a35413ba78"
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
