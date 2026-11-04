import Testing
import TidemarkCore

private let root = "/profiles"
private let uuid = "b2c8ae60-ceed-4ce1-a312-ca7d37b06fd8"
private let otherProfile = "aaa11111-1111-1111-1111-111111111111"

private func listing(_ result: ListingResult) -> AccountListing? {
    if case .success(let listing) = result { return listing }
    return nil
}

@Suite("resolveOrcaListing")
struct OrcaListingTests {
    @Test func noSelectionUsesDefault() {
        let result = resolveOrcaListing(
            selection: .none,
            profileNames: [uuid, otherProfile],
            profilesRoot: root
        )
        let value = listing(result)
        #expect(value?.current == "default")
        #expect(value?.entries == [
            ListingEntry(name: "default", configDir: nil, email: nil),
            ListingEntry(name: otherProfile, configDir: root + "/" + otherProfile + "/home", email: nil),
            ListingEntry(name: uuid, configDir: root + "/" + uuid + "/home", email: nil),
        ])
    }

    @Test func matchingProfileHomeBecomesCurrent() {
        let result = resolveOrcaListing(
            selection: .path(root + "/" + uuid + "/home"),
            profileNames: [uuid],
            profilesRoot: root
        )
        #expect(listing(result)?.current == uuid)
    }

    @Test func matchingProfileHomeIgnoresTrailingSlash() {
        let result = resolveOrcaListing(
            selection: .path(root + "/" + uuid + "/home/"),
            profileNames: [uuid],
            profilesRoot: root
        )
        #expect(listing(result)?.current == uuid)
    }

    @Test func unmatchedPathIsAppended() {
        let result = resolveOrcaListing(
            selection: .path("/elsewhere/carol/"),
            profileNames: [],
            profilesRoot: root
        )
        let value = listing(result)
        #expect(value?.current == "carol")
        #expect(value?.entries == [
            ListingEntry(name: "default", configDir: nil, email: nil),
            ListingEntry(name: "carol", configDir: "/elsewhere/carol", email: nil),
        ])
    }

    @Test func unreadableSelectionFails() {
        let result = resolveOrcaListing(
            selection: .unreadable,
            profileNames: [uuid],
            profilesRoot: root
        )
        #expect(result == .failure("계정 선택 파일 읽기 실패"))
    }

    @Test func profileNamesAreSorted() {
        let result = resolveOrcaListing(
            selection: .none,
            profileNames: ["ccc", "aaa", "bbb"],
            profilesRoot: root
        )
        #expect(listing(result)?.entries.map(\.name) == ["default", "aaa", "bbb", "ccc"])
    }
}
