import Testing
import TidemarkCore

private let fixture = """
{"current":"default","accounts":[{"name":"default","email":"jungmin.lee@imweb.me","five_hour":null,"seven_day":{"used":94,"resets_at":1793901600},"updated_at":1793780834,"best":false},{"name":"personal","email":"ljmjh4811@gmail.com","five_hour":null,"seven_day":null,"updated_at":null,"best":false}]}
"""

@Suite("parseCcaListing")
struct CcaListingTests {
    @Test func parsesRealFixture() {
        let listing = parseCcaListing(fixture, home: "/Users/jaime")
        #expect(listing?.current == "default")
        #expect(listing?.entries.count == 2)

        let first = listing?.entries.first
        #expect(first?.name == "default")
        #expect(first?.configDir == nil)
        #expect(first?.email == "jungmin.lee@imweb.me")

        let second = listing?.entries.last
        #expect(second?.name == "personal")
        #expect(second?.configDir == "/Users/jaime/.claude-accounts/personal")
        #expect(second?.email == "ljmjh4811@gmail.com")
    }

    @Test func nullEmailBecomesNil() {
        let json = #"{"current":"default","accounts":[{"name":"default","email":null}]}"#
        let listing = parseCcaListing(json, home: "/Users/jaime")
        #expect(listing?.entries.first?.email == nil)
        #expect(listing?.entries.first?.configDir == nil)
    }

    @Test func rejectsHumanTableOutput() {
        let table = """
        NAME     EMAIL
        default  jungmin.lee@imweb.me
        """
        #expect(parseCcaListing(table, home: "/Users/jaime") == nil)
    }
}
