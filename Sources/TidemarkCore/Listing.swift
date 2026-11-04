import Foundation

public struct ListingEntry: Equatable {
    public let name: String
    public let configDir: String?
    public let email: String?

    public init(name: String, configDir: String?, email: String?) {
        self.name = name
        self.configDir = configDir
        self.email = email
    }
}

public struct AccountListing: Equatable {
    public let current: String?
    public let entries: [ListingEntry]

    public init(current: String?, entries: [ListingEntry]) {
        self.current = current
        self.entries = entries
    }
}

public enum ListingResult: Equatable {
    case success(AccountListing)
    case failure(String)
}
