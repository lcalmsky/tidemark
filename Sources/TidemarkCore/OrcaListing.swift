import Foundation

public enum OrcaSelection: Equatable {
    case none
    case path(String)
    case unreadable
}

/// 선택 파일 값과 profile.json 이 있는 프로필 이름들로 계정 목록을 만든다.
public func resolveOrcaListing(
    selection: OrcaSelection,
    profileNames: [String],
    profilesRoot: String
) -> ListingResult {
    if case .unreadable = selection { return .failure("계정 선택 파일 읽기 실패") }

    var entries = [ListingEntry(name: "default", configDir: nil, email: nil)]
    for name in profileNames.sorted() {
        entries.append(ListingEntry(
            name: name,
            configDir: profilesRoot + "/" + name + "/home",
            email: nil
        ))
    }

    guard case .path(let selected) = selection else {
        return .success(AccountListing(current: "default", entries: entries))
    }
    let normalized = normalizePath(selected)
    if let match = entries.first(where: { $0.configDir.map(normalizePath) == normalized }) {
        return .success(AccountListing(current: match.name, entries: entries))
    }
    let name = URL(fileURLWithPath: normalized).lastPathComponent
    entries.append(ListingEntry(name: name, configDir: normalized, email: nil))
    return .success(AccountListing(current: name, entries: entries))
}
