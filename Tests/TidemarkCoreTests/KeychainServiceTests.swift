import Testing
import TidemarkCore

@Suite("keychainService")
struct KeychainServiceTests {
    @Test func defaultAccountUsesPlainService() {
        #expect(keychainService(for: nil) == "Claude Code-credentials")
    }

    @Test func ccaAccountGetsPathHashSuffix() {
        #expect(
            keychainService(for: "/Users/jaime/.claude-accounts/personal")
                == "Claude Code-credentials-33ccb883"
        )
    }

    @Test func orcaProfileHomeGetsPathHashSuffix() {
        let configDir = "/Users/jaime/Library/Application Support/orca/claude-profiles/"
            + "b2c8ae60-ceed-4ce1-a312-ca7d37b06fd8/home"
        #expect(keychainService(for: configDir) == "Claude Code-credentials-ca44c275")
    }
}
