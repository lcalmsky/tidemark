import Testing
import TidemarkCore

@Suite("normalizePath")
struct NormalizePathTests {
    @Test func removesTrailingSlash() {
        #expect(normalizePath("/a/b/") == "/a/b")
    }

    @Test func rootStaysRoot() {
        #expect(normalizePath("/") == "/")
    }

    @Test func leavesPathWithoutTrailingSlash() {
        #expect(normalizePath("/a/b") == "/a/b")
    }
}
