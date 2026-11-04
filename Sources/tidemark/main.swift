import AppKit
import Foundation
import TidemarkCore

enum AppInfo {
    static let version = "0.1.3"
}

// MARK: - 응답 모델

private struct ModelInfo: Codable {
    let display_name: String?
}

private struct LimitScope: Codable {
    let model: ModelInfo?
}

private struct Limit: Codable {
    let kind: String?
    let percent: Double?
    let resets_at: String?
    let scope: LimitScope?
}

private struct LimitsEnvelope: Codable {
    let limits: [Limit]?
}

// MARK: - 포맷 도우미

private enum Format {
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let manual: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    /// resets_at 은 소수점 이하 자릿수가 6자리까지 나오므로 ISO8601DateFormatter 가
    /// 그대로는 파싱하지 못한다. 소수점 이하를 잘라낸 뒤 파싱한다.
    static func parseTimestamp(_ raw: String) -> Date? {
        var trimmed = raw
        if let dot = trimmed.firstIndex(of: ".") {
            var end = trimmed.index(after: dot)
            while end < trimmed.endIndex, trimmed[end].isNumber {
                end = trimmed.index(after: end)
            }
            trimmed.removeSubrange(dot..<end)
        }
        if let d = isoPlain.date(from: trimmed) { return d }
        if let d = manual.date(from: trimmed) { return d }
        if let d = isoFractional.date(from: raw) { return d }
        return nil
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval) / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days >= 1 { return "\(days)d \(hours)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func remainingCompact(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval) / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days >= 1 { return "\(days)d\(hours)h" }
        if hours >= 1 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

private func roundedPercent(_ value: Double) -> Int {
    Int(value.rounded())
}

// MARK: - 계정

/// GUI 앱은 PATH 에 ~/.local/bin 이 없어서 절대 경로로 부른다.
private let ccaPath = NSHomeDirectory() + "/.local/bin/cca"
private let orcaProfilesRoot = NSHomeDirectory() + "/Library/Application Support/orca/claude-profiles"

private enum AccountSource: String {
    case cca
    case orca

    static var current: AccountSource {
        AccountSource(rawValue: UserDefaults.standard.string(forKey: "accountSource") ?? "") ?? .cca
    }
}

/// 계정 하나의 표시 상태. 이름이 default 면 configDir 가 nil 이다.
private struct AccountState {
    let name: String
    let configDir: String?
    let email: String?
    let plan: String?
    let limits: [Limit]
    let lastSuccess: Date?
    let lastError: String?
}

// MARK: - 프로세스

private func runCommand(
    _ executable: String,
    _ arguments: [String],
    timeout: TimeInterval = 10
) -> (exitCode: Int32?, stdout: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }

    do {
        try process.run()
    } catch {
        return (nil, "")
    }

    if finished.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        _ = finished.wait(timeout: .now() + 2)
        return (nil, "")
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// MARK: - 계정 목록

private func listCca() -> ListingResult {
    let result = runCommand(ccaPath, ["ls", "--json"])
    guard result.exitCode == 0 else { return .failure("cca 실행 실패") }
    guard let listing = parseCcaListing(result.stdout, home: NSHomeDirectory()) else {
        return .failure("cca 응답 파싱 실패")
    }
    return .success(listing)
}

private func readOrcaSelection() -> OrcaSelection {
    let path = orcaProfilesRoot + "/selected-host"
    guard FileManager.default.fileExists(atPath: path) else { return .none }
    guard let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8) else { return .unreadable }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .none : .path(trimmed)
}

private func listOrca() -> ListingResult {
    let selection = readOrcaSelection()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: orcaProfilesRoot)) ?? []
    let profileNames = names.filter {
        FileManager.default.fileExists(atPath: orcaProfilesRoot + "/" + $0 + "/profile.json")
    }
    return resolveOrcaListing(
        selection: selection,
        profileNames: profileNames,
        profilesRoot: orcaProfilesRoot
    )
}

// MARK: - 앱

private final class UsageBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var currentName: String?
    private var accounts: [AccountState] = []
    private var globalError: String?
    private var isFetching = false
    private var pendingFetch = false
    private var isSwitching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        renderTitle()
        fetch()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        RunLoop.main.add(timer, forMode: .common)

        let titleTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.renderTitle()
            switch AccountSource.current {
            case .cca:
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self = self else { return }
                    let result = runCommand(ccaPath, ["current"])
                    guard result.exitCode == 0 else { return }
                    let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    DispatchQueue.main.async {
                        if name != self.currentName { self.fetch() }
                    }
                }
            case .orca:
                let selection = readOrcaSelection()
                DispatchQueue.main.async {
                    switch selection {
                    case .unreadable:
                        if self.globalError == nil { self.fetch() }
                    case .none:
                        if self.currentName != "default" { self.fetch() }
                    case .path(let path):
                        let normalized = normalizePath(path)
                        let name = self.accounts.first {
                            $0.configDir.map(normalizePath) == normalized
                        }?.name ?? URL(fileURLWithPath: normalized).lastPathComponent
                        if name != self.currentName { self.fetch() }
                    }
                }
            }
        }
        RunLoop.main.add(titleTimer, forMode: .common)
    }

    // MARK: 상태 표시

    private static let titleHeight: CGFloat = 18
    private static let ringDiameter: CGFloat = 16
    private static let ringLineWidth: CGFloat = 2
    private static let segmentGap: CGFloat = 7
    private static let ringLetterFont = NSFont.systemFont(ofSize: 8, weight: .heavy)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    /// 조각 하나의 폭과 그리기 동작. 폭을 먼저 재야 이미지 크기를 정할 수 있다.
    private struct TitleItem {
        let width: CGFloat
        let render: (_ x: CGFloat, _ height: CGFloat) -> Void
    }

    private func renderTitle() {
        guard let button = statusItem.button else { return }
        button.image = titleImage()
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
    }

    private func titleImage() -> NSImage {
        let items = titleItems()
        let width = ceil(items.reduce(0) { $0 + $1.width })
        let size = NSSize(width: max(width, 1), height: Self.titleHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for item in items {
                item.render(x, size.height)
                x += item.width
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func titleItems() -> [TitleItem] {
        var items: [TitleItem] = []
        let current = accounts.first { $0.name == currentName }

        guard let account = current, account.lastSuccess != nil else {
            items.append(textItem("C …", font: Self.valueFont, color: .labelColor))
            let hasError = globalError != nil
                || current?.lastError != nil
                || (current == nil && accounts.contains { $0.lastError != nil })
            if hasError {
                items.append(textItem(" ?", font: Self.valueFont, color: .labelColor))
            }
            return items
        }

        var body: [TitleItem] = []
        for segment in titleSegments(account.limits) {
            if !body.isEmpty { body.append(gap(Self.segmentGap)) }
            body.append(ringItem(letter: segment.letter, percent: segment.percent))
            body.append(gap(4))
            body.append(textItem(
                "\(roundedPercent(segment.percent))%",
                font: Self.valueFont,
                color: color(for: segment.percent)
            ))
            if let raw = segment.resetsAt, let date = Format.parseTimestamp(raw) {
                body.append(gap(3))
                body.append(textItem(
                    Format.remainingCompact(date.timeIntervalSinceNow),
                    font: Self.timeFont,
                    color: .secondaryLabelColor
                ))
            }
        }

        if account.lastError != nil {
            body.append(textItem(" ?", font: Self.valueFont, color: .labelColor))
        }
        items.append(contentsOf: body)
        return items
    }

    /// 한도 종류마다 고정된 색. 경고색(주황·빨강)과 겹치지 않는 색만 쓴다.
    private func badgeColor(for letter: String) -> NSColor {
        switch letter {
        case "S": return .systemTeal
        case "W": return .systemIndigo
        case "F": return .systemPurple
        default: return .systemGray
        }
    }

    private func textItem(_ text: String, font: NSFont, color: NSColor) -> TitleItem {
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let size = string.size()
        return TitleItem(width: size.width) { x, height in
            string.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
        }
    }

    private func gap(_ width: CGFloat) -> TitleItem {
        TitleItem(width: width) { _, _ in }
    }

    /// 12 시 방향에서 시계 방향으로 채우는 원형 게이지. 가운데에 한도 글자를 넣는다.
    /// 채움색은 50% 까지 한도 색이고, 75% 까지 주황으로, 100% 까지 빨강으로 조금씩 바뀐다.
    private func ringItem(letter: String, percent: Double) -> TitleItem {
        let diameter = Self.ringDiameter
        let lineWidth = Self.ringLineWidth
        let tint = badgeColor(for: letter)
        let label = NSAttributedString(string: letter, attributes: [
            .font: Self.ringLetterFont,
            .foregroundColor: tint,
        ])
        let labelSize = label.size()
        let fraction = min(max(percent / 100, 0), 1)
        return TitleItem(width: diameter) { x, totalHeight in
            let center = NSPoint(x: x + diameter / 2, y: totalHeight / 2)
            let radius = (diameter - lineWidth) / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()

            label.draw(at: NSPoint(
                x: center.x - labelSize.width / 2,
                y: center.y - labelSize.height / 2
            ))

            guard fraction > 0 else { return }
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * CGFloat(fraction),
                clockwise: true
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            // 시스템 색은 다크·라이트 모드에 따라 달라서, 그리는 시점에 섞는다.
            Self.rampColor(tint: tint, percent: percent).setStroke()
            arc.stroke()
        }
    }

    private static func rampColor(tint: NSColor, percent: Double) -> NSColor {
        if percent <= 50 { return tint }
        if percent <= 75 {
            return tint.blended(withFraction: CGFloat((percent - 50) / 25), of: .systemOrange) ?? tint
        }
        let fraction = CGFloat(min((percent - 75) / 25, 1))
        return NSColor.systemOrange.blended(withFraction: fraction, of: .systemRed) ?? .systemOrange
    }

    private func color(for percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .labelColor
    }

    private func titleSegments(
        _ limits: [Limit]
    ) -> [(letter: String, percent: Double, resetsAt: String?)] {
        var segments: [(letter: String, percent: Double, resetsAt: String?)] = []
        for limit in limits {
            guard let kind = limit.kind, let percent = limit.percent else { continue }
            let letter: String
            switch kind {
            case "session":
                letter = "S"
            case "weekly_all":
                letter = "W"
            case "weekly_scoped":
                guard let name = limit.scope?.model?.display_name,
                      let first = name.first else { continue }
                letter = String(first).uppercased()
            default:
                continue
            }
            segments.append((letter, percent, limit.resets_at))
        }
        return segments
    }

    // MARK: 메뉴

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let source = AccountSource.current
        let isOrca = source == .orca

        for account in accounts {
            let header = NSMenuItem(
                title: headerTitle(account, isOrca: isOrca),
                action: isOrca ? nil : #selector(selectAccount(_:)),
                keyEquivalent: ""
            )
            header.target = self
            header.representedObject = account.name
            header.isEnabled = true
            header.state = account.name == currentName ? .on : .off
            menu.addItem(header)

            for limit in account.limits {
                guard let kind = limit.kind, let percent = limit.percent else { continue }
                let label: String
                switch kind {
                case "session": label = "세션"
                case "weekly_all": label = "주간"
                case "weekly_scoped": label = limit.scope?.model?.display_name ?? "주간"
                default: continue
                }

                var text = "\(label)  \(roundedPercent(percent))%"
                if let raw = limit.resets_at, let date = Format.parseTimestamp(raw) {
                    text += "  · 리셋까지 " + Format.remaining(date.timeIntervalSinceNow)
                }
                let item = disabledItem(text)
                item.indentationLevel = 1
                menu.addItem(item)
            }

            if let lastSuccess = account.lastSuccess {
                let item = disabledItem("갱신: " + Format.clock.string(from: lastSuccess))
                item.indentationLevel = 1
                menu.addItem(item)
            }
            if let lastError = account.lastError {
                let item = disabledItem("오류: " + lastError)
                item.indentationLevel = 1
                menu.addItem(item)
            }

            menu.addItem(.separator())
        }

        menu.addItem(disabledItem(
            isOrca ? "계정 전환은 Orca 에서" : "전환은 새로 여는 claude 세션부터 적용"
        ))
        if let globalError = globalError {
            menu.addItem(disabledItem("오류: " + globalError))
        }

        menu.addItem(sourceMenuItem())
        menu.addItem(autoSwitchItem(isOrca: isOrca))

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = true
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "종료", action: #selector(quitNow), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
    }

    private func headerTitle(_ account: AccountState, isOrca: Bool) -> String {
        var title = account.name
        if isOrca {
            title = account.name == "default" ? "default" : String(account.name.prefix(8))
        }
        if let email = account.email, !email.isEmpty {
            title += " · " + email
        }
        if let plan = account.plan, !plan.isEmpty {
            title += " (\(plan))"
        }
        return title
    }

    private func sourceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "계정 출처", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for source in [AccountSource.cca, AccountSource.orca] {
            let entry = NSMenuItem(
                title: source == .cca ? "cca" : "Orca",
                action: #selector(selectSource(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = source.rawValue
            entry.isEnabled = true
            entry.state = source == AccountSource.current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        item.isEnabled = true
        return item
    }

    private func autoSwitchItem(isOrca: Bool) -> NSMenuItem {
        let item = NSMenuItem(
            title: "자동 전환 (95%)",
            action: #selector(toggleAutoSwitch(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = !isOrca
        item.state = UserDefaults.standard.bool(forKey: "autoSwitch") ? .on : .off
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, name != currentName else { return }
        switchAccount(to: name) { [weak self] success in
            if success { self?.fetch() }
        }
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let source = AccountSource(rawValue: raw),
              source != AccountSource.current else { return }
        UserDefaults.standard.set(source.rawValue, forKey: "accountSource")
        accounts = []
        currentName = nil
        globalError = nil
        renderTitle()
        rebuildMenu()
        fetch()
    }

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "autoSwitch"), forKey: "autoSwitch")
        rebuildMenu()
        if AccountSource.current == .cca { evaluateAutoSwitch() }
    }

    private func switchAccount(to name: String, completion: ((Bool) -> Void)? = nil) {
        guard !isSwitching else { return }
        isSwitching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = runCommand(ccaPath, ["use", name])
            DispatchQueue.main.async {
                self.isSwitching = false
                switch result.exitCode {
                case 0:
                    self.currentName = name
                    self.globalError = nil
                    self.renderTitle()
                    self.rebuildMenu()
                    completion?(true)
                case 2:
                    self.globalError = "계정 전환 실패: 이름 오류"
                    self.renderTitle()
                    self.rebuildMenu()
                    completion?(false)
                case 3:
                    self.globalError = "계정 전환 실패: 없는 계정"
                    self.renderTitle()
                    self.rebuildMenu()
                    completion?(false)
                default:
                    self.globalError = "계정 전환 실패"
                    self.renderTitle()
                    self.rebuildMenu()
                    completion?(false)
                }
            }
        }
    }

    @objc private func refreshNow() {
        fetch()
    }

    @objc private func quitNow() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: 수집

    private func fetch() {
        // 조회 중에 계정이 바뀌면 진행 중인 조회는 이전 current 를 들고 오므로, 끝난 뒤 한 번 더 조회한다.
        guard !isFetching else {
            pendingFetch = true
            return
        }
        isFetching = true
        let previous = accounts
        let source = AccountSource.current

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result: ListingResult
            switch source {
            case .cca: result = listCca()
            case .orca: result = listOrca()
            }

            let listing: AccountListing
            switch result {
            case .failure(let reason):
                DispatchQueue.main.async {
                    self.isFetching = false
                    guard source == AccountSource.current else {
                        self.fetch()
                        return
                    }
                    self.globalError = reason
                    self.accounts = []
                    self.currentName = nil
                    self.renderTitle()
                    self.rebuildMenu()
                    if self.pendingFetch {
                        self.pendingFetch = false
                        self.fetch()
                    }
                }
                return
            case .success(let value):
                listing = value
            }

            let previousByName = Dictionary(
                previous.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var states: [AccountState] = []
            for entry in listing.entries {
                let prior = previousByName[entry.name]
                let email = entry.email ?? Self.accountEmail(for: entry.configDir) ?? prior?.email

                switch self.collect(configDir: entry.configDir) {
                case .success(let limits, let plan):
                    states.append(AccountState(
                        name: entry.name,
                        configDir: entry.configDir,
                        email: email,
                        plan: plan,
                        limits: limits,
                        lastSuccess: Date(),
                        lastError: nil
                    ))
                case .failure(let reason, let plan):
                    states.append(AccountState(
                        name: entry.name,
                        configDir: entry.configDir,
                        email: email,
                        plan: plan ?? prior?.plan,
                        limits: prior?.limits ?? [],
                        lastSuccess: prior?.lastSuccess,
                        lastError: reason
                    ))
                }
            }

            DispatchQueue.main.async {
                self.isFetching = false
                guard source == AccountSource.current else {
                    self.fetch()
                    return
                }
                self.currentName = listing.current
                self.accounts = states
                self.globalError = nil
                self.renderTitle()
                self.rebuildMenu()
                if self.pendingFetch {
                    self.pendingFetch = false
                    self.fetch()
                } else if source == .cca {
                    self.evaluateAutoSwitch()
                }
            }
        }
    }

    // MARK: 자동 전환

    private static let autoSwitchThreshold: Double = 95

    private static func percent(of kind: String, in limits: [Limit]) -> Double? {
        limits.first { $0.kind == kind }?.percent
    }

    private func evaluateAutoSwitch() {
        guard UserDefaults.standard.bool(forKey: "autoSwitch"),
              let from = currentName else { return }

        let usages = accounts.map { account in
            AccountUsage(
                name: account.name,
                ok: account.lastError == nil && account.lastSuccess != nil,
                sessionPercent: Self.percent(of: "session", in: account.limits),
                weeklyAllPercent: Self.percent(of: "weekly_all", in: account.limits)
            )
        }
        guard let decision = autoSwitchDecision(
            currentName: from,
            accounts: usages,
            threshold: Self.autoSwitchThreshold
        ) else { return }

        switchAccount(to: decision.target) { [weak self] success in
            guard success, let self = self else { return }
            self.postNotification(
                "자동 전환: \(from) → \(decision.target) (\(decision.label) \(decision.percent)%)"
            )
        }
    }

    /// 개발용 바이너리는 앱 번들이 없어 UserNotifications 를 쓸 수 없으므로 osascript 로 띄운다.
    private func postNotification(_ body: String) {
        DispatchQueue.global(qos: .utility).async {
            let escaped = body
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            _ = runCommand("/usr/bin/osascript", [
                "-e", "display notification \"\(escaped)\" with title \"Tidemark\"",
            ])
        }
    }

    private enum Outcome {
        case success([Limit], String?)
        case failure(String, String?)
    }

    private func collect(configDir: String?) -> Outcome {
        let service = keychainService(for: configDir)
        guard let credentials = Self.credentials(service: service) else {
            return .failure("토큰 조회 실패", nil)
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let semaphore = DispatchSemaphore(value: 0)
        var status: Int?
        var body: Data?
        var transportError: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            status = (response as? HTTPURLResponse)?.statusCode
            body = data
            if let error = error { transportError = error.localizedDescription }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return .failure("시간 초과", credentials.plan)
        }
        if transportError != nil {
            return .failure("네트워크 오류", credentials.plan)
        }
        guard let code = status else {
            return .failure("응답 없음", credentials.plan)
        }
        guard code == 200 else {
            return .failure("HTTP \(code)", credentials.plan)
        }
        guard let data = body, let limits = Self.decodeLimits(data) else {
            return .failure("응답 파싱 실패", credentials.plan)
        }
        return .success(limits, credentials.plan)
    }

    private static func decodeLimits(_ data: Data) -> [Limit]? {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([Limit].self, from: data) {
            return array
        }
        if let envelope = try? decoder.decode(LimitsEnvelope.self, from: data) {
            return envelope.limits
        }
        return nil
    }

    private struct Credentials {
        let token: String
        let plan: String?
    }

    private static func accountEmail(for configDir: String?) -> String? {
        let path = configDir.map { $0 + "/.claude.json" } ?? (NSHomeDirectory() + "/.claude.json")
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any],
              let email = oauth["emailAddress"] as? String, !email.isEmpty else { return nil }
        return email
    }

    /// 주어진 서비스의 항목만 읽는다. 다른 계정 항목으로 내려가지 않는다.
    /// 토큰은 어떤 경로로도 출력하지 않는다.
    private static func credentials(service: String) -> Credentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let oauth = root["claudeAiOauth"] as? [String: Any]
        let token: String?
        if let value = oauth?["accessToken"] as? String, !value.isEmpty {
            token = value
        } else if let value = root["accessToken"] as? String, !value.isEmpty {
            token = value
        } else {
            token = nil
        }
        guard let token = token else { return nil }
        return Credentials(token: token, plan: oauth?["subscriptionType"] as? String)
    }
}

if CommandLine.arguments.contains("--version") {
    print("tidemark \(AppInfo.version)")
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private let usageBar = UsageBar()
application.delegate = usageBar
application.run()
