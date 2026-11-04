import Foundation

private struct CcaListing: Decodable {
    let current: String?
    let accounts: [CcaAccountEntry]
}

private struct CcaAccountEntry: Decodable {
    let name: String
    let email: String?
}

/// `cca ls --json` 출력을 계정 목록으로 바꾼다. 이름이 default 면 configDir 가 nil 이다.
public func parseCcaListing(_ stdout: String, home: String) -> AccountListing? {
    guard let data = stdout.data(using: .utf8),
          let list = try? JSONDecoder().decode(CcaListing.self, from: data) else {
        return nil
    }
    let entries = list.accounts.map { entry in
        ListingEntry(
            name: entry.name,
            configDir: entry.name == "default" ? nil : home + "/.claude-accounts/" + entry.name,
            email: entry.email
        )
    }
    return AccountListing(current: list.current, entries: entries)
}
