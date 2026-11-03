import Foundation
import Observation

struct LimitWindow: Sendable {
    var usedPercent: Double
    var resetsAt: Date?
}

struct TokenTotals: Sendable {
    var tokens = 0
    var cost: Double = 0
    /// Some usage came from a model without a known price, so `cost` is a lower bound.
    var unpriced = false

    mutating func add(tokens: Int, cost: Double?) {
        self.tokens += tokens
        if let cost { self.cost += cost } else if tokens > 0 { unpriced = true }
    }

    static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(tokens: lhs.tokens + rhs.tokens, cost: lhs.cost + rhs.cost, unpriced: lhs.unpriced || rhs.unpriced)
    }
}

struct ProviderUsage: Sendable {
    var plan: String?
    var session: LimitWindow?
    var week: LimitWindow?
    var today = TokenTotals()
    var last7Days = TokenTotals()
    var note: String?
    var loaded = false
}

@Observable
@MainActor
final class UsageStore {
    private(set) var claude = ProviderUsage()
    private(set) var codex = ProviderUsage()
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private let claudeLogs = ClaudeLogScanner()
    @ObservationIgnored private let codexLogs = CodexLogScanner()

    func refreshIfStale() {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        refresh()
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        lastRefresh = Date()
        Task {
            async let limits = ClaudeLimits.fetch()
            async let claudeTotals = claudeLogs.totals()
            async let codexUsage = codexLogs.usage()

            var newClaude = ProviderUsage(loaded: true)
            let (plan, session, week, note) = await limits
            newClaude.plan = plan
            newClaude.note = note
            newClaude.session = session
            newClaude.week = week
            if session != nil || week != nil {
                ClaudeLimits.saveLastKnown(session: session, week: week)
            } else if note != ClaudeLimits.signedOutNote, let last = ClaudeLimits.lastKnown() {
                // Claude Code renews its login only while it runs, so between sessions show the
                // last numbers it got, the way Codex's come from its last log entry.
                newClaude.session = last.session
                newClaude.week = last.week
                newClaude.note = "Updated \(last.age) ago"
            }
            (newClaude.today, newClaude.last7Days) = await claudeTotals

            claude = newClaude
            codex = await codexUsage
            refreshing = false
        }
    }
}

// MARK: Shared parsing helpers

enum UsageParsing {
    static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }

    // ISO8601DateFormatter is thread-safe; creating one per line would dominate scan time.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plainFormatter = ISO8601DateFormatter()

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Today and the rolling last 7 days (including today), from per-day buckets.
    static func summarize(_ buckets: [Date: TokenTotals]) -> (TokenTotals, TokenTotals) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var todayTotals = TokenTotals(), weekTotals = TokenTotals()
        for (day, totals) in buckets where day >= weekStart {
            weekTotals = weekTotals + totals
            if day == today { todayTotals = todayTotals + totals }
        }
        return (todayTotals, weekTotals)
    }

    /// Calls `body` for each complete line in `url` past `offset` that contains one of the
    /// markers; returns the new offset. Partial trailing lines are left for the next scan.
    /// Reads in chunks with a pool per chunk so a week of transcripts never sits in memory at once.
    static func readNewLines(_ url: URL, from offset: UInt64, markers: [Data], _ body: (Data) -> Void) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }
        var consumed = offset
        var pending = Data()
        var reading = true
        while reading {
            autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty else {
                    reading = false
                    return
                }
                pending.append(chunk)
                guard let lastNewline = pending.lastIndex(of: 0x0A) else { return }
                var lineStart = pending.startIndex
                while lineStart <= lastNewline {
                    let lineEnd = pending[lineStart...lastNewline].firstIndex(of: 0x0A) ?? lastNewline
                    let line = pending[lineStart..<lineEnd]
                    if markers.contains(where: { line.range(of: $0) != nil }) { body(Data(line)) }
                    lineStart = lineEnd + 1
                }
                consumed += UInt64(lastNewline - pending.startIndex + 1)
                pending = Data(pending[(lastNewline + 1)...])
            }
        }
        return consumed
    }

    /// `.jsonl` files under `root` modified in the last 8 days.
    static func recentLogFiles(under root: URL) -> [(url: URL, size: UInt64)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = Date().addingTimeInterval(-8 * 86_400)
        var files: [(URL, UInt64)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate, modified > cutoff,
                  let size = values.fileSize else { continue }
            files.append((url, UInt64(size)))
        }
        return files
    }
}

// MARK: Claude

/// Live 5-hour and weekly limits, using the OAuth token Claude Code keeps in the keychain.
/// The token is read through /usr/bin/security (which Claude Code itself uses), so there's
/// no keychain prompt. It is never refreshed here: rotating it would sign Claude Code out.
enum ClaudeLimits {
    static let offlineNote = "Offline"
    static let signedOutNote = "Sign in to Claude Code to see limits"

    static func fetch() async -> (plan: String?, session: LimitWindow?, week: LimitWindow?, note: String?) {
        guard let credentials = await Task.detached(operation: readCredentials).value else {
            return (nil, nil, nil, signedOutNote)
        }
        let plan = credentials.plan?.capitalized
        if let expiry = credentials.expiresAt, expiry < Date() {
            return (plan, nil, nil, "Login expired — run claude to refresh")
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return (plan, nil, nil, nil) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { return (plan, nil, nil, "Login expired — run claude to refresh") }
            guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (plan, nil, nil, "Limits unavailable (HTTP \(status))")
            }
            return (plan, window(json["five_hour"]), window(json["seven_day"]), nil)
        } catch {
            return (plan, nil, nil, offlineNote)
        }
    }

    static func saveLastKnown(session: LimitWindow?, week: LimitWindow?) {
        var saved: [String: Double] = ["date": Date().timeIntervalSince1970]
        saved["session"] = session?.usedPercent
        saved["sessionResets"] = session?.resetsAt?.timeIntervalSince1970
        saved["week"] = week?.usedPercent
        saved["weekResets"] = week?.resetsAt?.timeIntervalSince1970
        UserDefaults.standard.set(saved, forKey: "claudeLastLimits")
    }

    /// The last limits fetched, with any window that has since reset shown as unused.
    static func lastKnown() -> (session: LimitWindow?, week: LimitWindow?, age: String)? {
        guard let saved = UserDefaults.standard.dictionary(forKey: "claudeLastLimits") as? [String: Double],
              let date = saved["date"] else { return nil }
        func window(_ key: String) -> LimitWindow? {
            guard let used = saved[key] else { return nil }
            let resetsAt = saved[key + "Resets"].map(Date.init(timeIntervalSince1970:))
            if let resetsAt, resetsAt < Date() { return LimitWindow(usedPercent: 0, resetsAt: nil) }
            return LimitWindow(usedPercent: used, resetsAt: resetsAt)
        }
        let minutes = max(1, Int(Date().timeIntervalSince1970 - date) / 60)
        let age = minutes < 60 ? "\(minutes)m" : minutes < 1440 ? "\(minutes / 60)h" : "\(minutes / 1440)d"
        return (window("session"), window("week"), age)
    }

    private static func window(_ value: Any?) -> LimitWindow? {
        guard let dict = value as? [String: Any], let used = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
        return LimitWindow(usedPercent: used, resetsAt: UsageParsing.date(dict["resets_at"] as? String))
    }

    private struct Credentials: Sendable {
        let token: String
        let expiresAt: Date?
        let plan: String?
    }

    @Sendable private static func readCredentials() -> Credentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var data = Data()
        if (try? process.run()) != nil {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        }
        if process.terminationStatus != 0 || data.isEmpty {
            // Older installs keep credentials in a file instead of the keychain.
            data = (try? Data(contentsOf: UsageParsing.home.appendingPathComponent(".claude/.credentials.json"))) ?? Data()
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        let expiry = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(token: token, expiresAt: expiry, plan: oauth["subscriptionType"] as? String)
    }
}

/// API-equivalent prices in USD per million tokens.
enum ClaudePricing {
    struct Rate { let input, output, write5m, write1h, read: Double }

    static func rate(for model: String) -> Rate? {
        let m = model.lowercased()
        if m.contains("fable-5-1") || m.contains("mythos-5-1") { return Rate(input: 10, output: 50, write5m: 12.5, write1h: 20, read: 0.25) }
        if m.contains("fable") || m.contains("mythos") { return Rate(input: 10, output: 50, write5m: 12.5, write1h: 20, read: 1) }
        if m.contains("opus-5-5") { return Rate(input: 4, output: 20, write5m: 5, write1h: 8, read: 0.2) }
        if ["opus-5", "opus-4-8", "opus-4-7", "opus-4-6", "opus-4-5"].contains(where: m.contains) {
            return Rate(input: 5, output: 25, write5m: 6.25, write1h: 10, read: 0.5)
        }
        if m.contains("opus") { return Rate(input: 15, output: 75, write5m: 18.75, write1h: 30, read: 1.5) }
        if m.contains("sonnet-5") { return Rate(input: 2, output: 10, write5m: 2.5, write1h: 4, read: 0.2) }
        if m.contains("sonnet") { return Rate(input: 3, output: 15, write5m: 3.75, write1h: 6, read: 0.3) }
        if m.contains("haiku-5") { return Rate(input: 0.1, output: 0.5, write5m: 0.125, write1h: 0.2, read: 0.01) }
        if m.contains("haiku-4-5") { return Rate(input: 1, output: 5, write5m: 1.25, write1h: 2, read: 0.1) }
        if m.contains("haiku") { return Rate(input: 0.8, output: 4, write5m: 1, write1h: 1.6, read: 0.08) }
        return nil
    }

    static func cost(model: String, input: Int, output: Int, write5m: Int, write1h: Int, read: Int) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        // Haiku 5.5 bills 5x for prompts over 100K tokens.
        let prompt = input + write5m + write1h + read
        let multiplier = model.contains("haiku-5") && prompt > 100_000 ? 5.0 : 1.0
        let dollars = Double(input) * rate.input + Double(output) * rate.output + Double(write5m) * rate.write5m
            + Double(write1h) * rate.write1h + Double(read) * rate.read
        return dollars * multiplier / 1_000_000
    }
}

/// Incrementally reads Claude Code transcripts (~/.claude/projects/**/*.jsonl), only parsing
/// bytes appended since the previous scan.
actor ClaudeLogScanner {
    private var offsets: [String: UInt64] = [:]
    private var seen = Set<String>()
    private var buckets: [Date: TokenTotals] = [:]
    private let markers = [Data("\"output_tokens\"".utf8)]

    func totals() -> (TokenTotals, TokenTotals) {
        let root = UsageParsing.home.appendingPathComponent(".claude/projects")
        for file in UsageParsing.recentLogFiles(under: root) {
            var offset = offsets[file.url.path] ?? 0
            if file.size < offset { offset = 0 }
            guard file.size > offset else { continue }
            offsets[file.url.path] = UsageParsing.readNewLines(file.url, from: offset, markers: markers) { parse($0) }
        }
        return UsageParsing.summarize(buckets)
    }

    private func parse(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let date = UsageParsing.date(json["timestamp"] as? String) else { return }
        // Claude Code writes one line per content block, all repeating the same usage.
        let key = "\(message["id"] as? String ?? ""):\(json["requestId"] as? String ?? "")"
        if key != ":" { guard seen.insert(key).inserted else { return } }

        let model = message["model"] as? String ?? ""
        let input = UsageParsing.int(usage["input_tokens"])
        let output = UsageParsing.int(usage["output_tokens"])
        let creation = UsageParsing.int(usage["cache_creation_input_tokens"])
        let read = UsageParsing.int(usage["cache_read_input_tokens"])
        let split = usage["cache_creation"] as? [String: Any]
        let write1h = UsageParsing.int(split?["ephemeral_1h_input_tokens"])
        let write5m = split == nil ? creation : UsageParsing.int(split?["ephemeral_5m_input_tokens"])
        let tokens = input + output + creation + read
        guard tokens > 0 else { return }

        let cost = ClaudePricing.cost(model: model, input: input, output: output, write5m: write5m, write1h: write1h, read: read)
        buckets[Calendar.current.startOfDay(for: date), default: TokenTotals()].add(tokens: tokens, cost: cost)
    }
}

// MARK: Codex

/// Reads Codex CLI/app session logs (~/.codex/sessions/**/rollout-*.jsonl). Each
/// `token_count` event carries cumulative token usage plus the account's rate limits.
actor CodexLogScanner {
    private struct FileState {
        var offset: UInt64 = 0
        var model = ""
        var lastTotal: (input: Int, cached: Int, output: Int)?
    }

    private struct Limits {
        var date: Date
        var primary: LimitWindow?
        var secondary: LimitWindow?
        var plan: String?
    }

    private var files: [String: FileState] = [:]
    private var buckets: [Date: TokenTotals] = [:]
    private var latest: Limits?
    private let markers = [Data("\"token_count\"".utf8), Data("\"turn_context\"".utf8)]

    func usage() -> ProviderUsage {
        let root = UsageParsing.home.appendingPathComponent(".codex/sessions")
        for file in UsageParsing.recentLogFiles(under: root) {
            var state = files[file.url.path] ?? FileState()
            if file.size < state.offset { state = FileState() }
            guard file.size > state.offset else { continue }
            state.offset = UsageParsing.readNewLines(file.url, from: state.offset, markers: markers) { parse($0, into: &state) }
            files[file.url.path] = state
        }

        var usage = ProviderUsage(loaded: true)
        if let latest {
            usage.plan = latest.plan?.capitalized
            usage.session = current(latest.primary)
            usage.week = current(latest.secondary)
        } else {
            let installed = FileManager.default.fileExists(atPath: root.path)
            usage.note = installed ? "No Codex sessions this week" : "Codex not found (~/.codex)"
        }
        (usage.today, usage.last7Days) = UsageParsing.summarize(buckets)
        return usage
    }

    /// Limits are only reported when Codex makes a request, so a window that has since
    /// reset is shown as unused rather than stale.
    private func current(_ window: LimitWindow?) -> LimitWindow? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt, resetsAt < Date() { return LimitWindow(usedPercent: 0, resetsAt: nil) }
        return window
    }

    private func parse(_ line: Data, into state: inout FileState) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else { return }
        let type = json["type"] as? String
        if type == "turn_context" {
            if let model = payload["model"] as? String { state.model = model }
            return
        }
        guard payload["type"] as? String == "token_count",
              let date = UsageParsing.date(json["timestamp"] as? String) else { return }

        if let limits = payload["rate_limits"] as? [String: Any], date >= (latest?.date ?? .distantPast) {
            latest = Limits(date: date, primary: window(limits["primary"], eventDate: date),
                            secondary: window(limits["secondary"], eventDate: date), plan: limits["plan_type"] as? String)
        }

        guard let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else { return }
        let current = (input: UsageParsing.int(total["input_tokens"]),
                       cached: UsageParsing.int(total["cached_input_tokens"]),
                       output: UsageParsing.int(total["output_tokens"]))
        var delta = current
        if let previous = state.lastTotal {
            delta = (current.input - previous.input, current.cached - previous.cached, current.output - previous.output)
            if delta.input < 0 || delta.output < 0 {
                let last = info["last_token_usage"] as? [String: Any]
                delta = (UsageParsing.int(last?["input_tokens"]), UsageParsing.int(last?["cached_input_tokens"]),
                         UsageParsing.int(last?["output_tokens"]))
            }
        }
        state.lastTotal = current
        // Cached input is a subset of input.
        let tokens = delta.input + delta.output
        guard tokens > 0 else { return }
        let cost = CodexPricing.cost(model: state.model, input: delta.input, cached: max(delta.cached, 0), output: delta.output)
        buckets[Calendar.current.startOfDay(for: date), default: TokenTotals()].add(tokens: tokens, cost: cost)
    }

    private func window(_ value: Any?, eventDate: Date) -> LimitWindow? {
        guard let dict = value as? [String: Any], let used = (dict["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        var resetsAt: Date?
        if let epoch = (dict["resets_at"] as? NSNumber)?.doubleValue {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let seconds = (dict["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resetsAt = eventDate.addingTimeInterval(seconds)
        }
        return LimitWindow(usedPercent: used, resetsAt: resetsAt)
    }
}

/// OpenAI API prices in USD per million tokens, for models with published pricing.
/// Anything else is reported as unpriced rather than guessed.
enum CodexPricing {
    static func cost(model: String, input: Int, cached: Int, output: Int) -> Double? {
        let m = model.lowercased()
        let rate: (input: Double, cached: Double, output: Double)
        if m.hasPrefix("gpt-5") && m.contains("mini") {
            rate = (0.25, 0.025, 2)
        } else if m == "gpt-5" || m == "gpt-5-codex" || m.hasPrefix("gpt-5.1") {
            rate = (1.25, 0.125, 10)
        } else {
            return nil
        }
        let uncached = max(input - cached, 0)
        return (Double(uncached) * rate.input + Double(cached) * rate.cached + Double(output) * rate.output) / 1_000_000
    }
}
