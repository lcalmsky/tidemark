import AppKit
import CryptoKit
import Foundation

enum AppInfo {
    static let version = "0.1.1"
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

/// Orca 가 쓰는 프로필 선택 파일. 앱 밖에서 관리되는 외부 의존이다.
private let selectedHostPath = NSHomeDirectory()
    + "/Library/Application Support/orca/claude-profiles/selected-host"

/// 현재 선택된 Claude 계정. configDir 가 nil 이면 기본 계정(~/.claude)을 뜻한다.
private struct Account {
    let configDir: String?
    let email: String?
    let plan: String?

    var displayName: String {
        if let email = email, !email.isEmpty { return email }
        guard let configDir = configDir else { return "default" }
        let trimmed = configDir.hasSuffix("/") ? String(configDir.dropLast()) : configDir
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? trimmed : name
    }

    var menuTitle: String {
        var title = "계정: " + displayName
        if let plan = plan, !plan.isEmpty { title += " (\(plan))" }
        return title
    }
}

// MARK: - 앱

private final class UsageBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var limits: [Limit] = []
    private var account: Account?
    private var lastFetchedConfigDir: String?
    private var lastSuccess: Date?
    private var lastError: String?
    private var isFetching = false

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

        // 남은 시간 표시를 갱신하고, 계정이 바뀌었을 때만 수집을 다시 건다.
        let titleTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.renderTitle()
            if (try? Self.currentConfigDir()) != self.lastFetchedConfigDir {
                self.fetch()
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

        if lastSuccess == nil {
            items.append(textItem("C …", font: Self.valueFont, color: .labelColor))
            if lastError != nil {
                items.append(textItem(" ?", font: Self.valueFont, color: .labelColor))
            }
            return items
        }

        var body: [TitleItem] = []
        for segment in titleSegments() {
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

        if lastError != nil {
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
        case "F": return .systemPink
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
    /// 경고 구간(75% 이상)에서는 채움색이 한도 색 대신 경고색이 된다.
    private func ringItem(letter: String, percent: Double) -> TitleItem {
        let diameter = Self.ringDiameter
        let lineWidth = Self.ringLineWidth
        let tint = badgeColor(for: letter)
        let fill = percent >= 75 ? color(for: percent) : tint
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
            fill.setStroke()
            arc.stroke()
        }
    }

    private func color(for percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .labelColor
    }

    private func titleSegments() -> [(letter: String, percent: Double, resetsAt: String?)] {
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

        let current = account ?? Account(configDir: try? Self.currentConfigDir(), email: nil, plan: nil)
        menu.addItem(disabledItem(current.menuTitle))
        menu.addItem(.separator())

        for limit in limits {
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
            menu.addItem(disabledItem(text))
        }

        menu.addItem(.separator())

        if let lastSuccess = lastSuccess {
            menu.addItem(disabledItem("갱신: " + Format.clock.string(from: lastSuccess)))
        }
        if let lastError = lastError {
            menu.addItem(disabledItem("오류: " + lastError))
        }

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

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshNow() {
        fetch()
    }

    @objc private func quitNow() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: 수집

    private func fetch() {
        guard !isFetching else { return }
        let configDir: String?
        do {
            configDir = try Self.currentConfigDir()
        } catch {
            // 어느 계정인지 모르는 채로 기본 계정 토큰을 쓰지 않는다. 이전 계정의 수치도 지운다.
            account = nil
            limits = []
            lastSuccess = nil
            lastFetchedConfigDir = nil
            lastError = "계정 선택 파일 읽기 실패"
            renderTitle()
            rebuildMenu()
            return
        }
        isFetching = true
        lastFetchedConfigDir = configDir

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let outcome = self.collect(configDir: configDir)
            DispatchQueue.main.async {
                self.isFetching = false
                switch outcome {
                case .success(let limits, let account):
                    self.apply(account)
                    self.limits = limits
                    self.lastSuccess = Date()
                    self.lastError = nil
                case .failure(let reason, let account):
                    self.apply(account)
                    self.lastError = reason
                }
                self.renderTitle()
                self.rebuildMenu()
            }
        }
    }

    /// 계정이 바뀌면 이전 계정의 수치가 새 이름 아래 남지 않도록 지운다.
    private func apply(_ account: Account) {
        if account.configDir != self.account?.configDir {
            limits = []
            lastSuccess = nil
        }
        self.account = account
    }

    private enum Outcome {
        case success([Limit], Account)
        case failure(String, Account)
    }

    private func collect(configDir: String?) -> Outcome {
        let service = Self.keychainService(for: configDir)
        guard let credentials = Self.credentials(service: service) else {
            return .failure("토큰 조회 실패", Self.account(configDir: configDir, plan: nil))
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

        let account = Self.account(configDir: configDir, plan: credentials.plan)

        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return .failure("시간 초과", account)
        }
        if transportError != nil {
            return .failure("네트워크 오류", account)
        }
        guard let code = status else {
            return .failure("응답 없음", account)
        }
        guard code == 200 else {
            return .failure("HTTP \(code)", account)
        }
        guard let data = body, let limits = Self.decodeLimits(data) else {
            return .failure("응답 파싱 실패", account)
        }
        return .success(limits, account)
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

    private struct SelectionUnreadable: Error {}

    /// 선택된 config 디렉터리. nil 이면 기본 계정(~/.claude)이다.
    /// 선택 파일이 없거나 비어 있으면 기본 계정이다. Orca 는 기본 계정을 고르면 빈 내용을 쓴다.
    /// 파일이 있는데 읽지 못하면 오류로 던진다.
    private static func currentConfigDir() throws -> String? {
        guard FileManager.default.fileExists(atPath: selectedHostPath) else { return nil }
        guard let data = FileManager.default.contents(atPath: selectedHostPath),
              let raw = String(data: data, encoding: .utf8) else { throw SelectionUnreadable() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 기본이 아닌 config 디렉터리의 키체인 항목에는 경로 SHA-256 앞 8자리가 붙는다.
    private static func keychainService(for configDir: String?) -> String {
        guard let configDir = configDir else { return "Claude Code-credentials" }
        let digest = SHA256.hash(data: Data(configDir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + String(hex.prefix(8))
    }

    private static func account(configDir: String?, plan: String?) -> Account {
        Account(configDir: configDir, email: accountEmail(for: configDir), plan: plan)
    }

    private static func accountEmail(for configDir: String?) -> String? {
        let path = configDir.map { $0 + "/.claude.json" } ?? (NSHomeDirectory() + "/.claude.json")
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any],
              let email = oauth["emailAddress"] as? String, !email.isEmpty else { return nil }
        return email
    }

    /// 선택된 계정의 항목만 읽는다. 다른 계정 항목으로 내려가지 않는다.
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
