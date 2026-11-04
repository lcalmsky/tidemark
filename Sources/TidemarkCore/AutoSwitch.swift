import Foundation

public struct AccountUsage: Equatable {
    public let name: String
    public let ok: Bool
    public let sessionPercent: Double?
    public let weeklyAllPercent: Double?

    public init(name: String, ok: Bool, sessionPercent: Double?, weeklyAllPercent: Double?) {
        self.name = name
        self.ok = ok
        self.sessionPercent = sessionPercent
        self.weeklyAllPercent = weeklyAllPercent
    }
}

public struct AutoSwitchDecision: Equatable {
    public let target: String
    public let label: String
    public let percent: Int

    public init(target: String, label: String, percent: Int) {
        self.target = target
        self.label = label
        self.percent = percent
    }
}

public func autoSwitchDecision(
    currentName: String,
    accounts: [AccountUsage],
    threshold: Double = 95
) -> AutoSwitchDecision? {
    guard let current = accounts.first(where: { $0.name == currentName }),
          current.ok else { return nil }

    let sessionOver = current.sessionPercent.map { $0 >= threshold } ?? false
    let weeklyOver = current.weeklyAllPercent.map { $0 >= threshold } ?? false
    guard sessionOver || weeklyOver else { return nil }

    var target: AccountUsage?
    var lowest = Double.infinity
    for account in accounts where account.name != currentName {
        guard account.ok,
              let candidateSession = account.sessionPercent,
              let candidateWeekly = account.weeklyAllPercent,
              candidateSession < threshold,
              candidateWeekly < threshold else { continue }
        if candidateSession < lowest {
            lowest = candidateSession
            target = account
        }
    }
    guard let target = target else { return nil }

    let label = sessionOver ? "세션" : "주간"
    let trigger = (sessionOver ? current.sessionPercent : current.weeklyAllPercent) ?? 0
    return AutoSwitchDecision(
        target: target.name,
        label: label,
        percent: Int(trigger.rounded())
    )
}
