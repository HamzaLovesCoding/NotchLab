import Foundation

/// Adds and removes the bundled `notch-hook` in Claude Code's and Codex's hook config, so
/// agent questions and approvals reach the notch. Everything else in those files is kept.
enum AgentHooks {
    struct SetupError: LocalizedError {
        let errorDescription: String?
    }

    private struct Event {
        let name: String
        let matcher: String?
        /// The agent waits on these, so they get the long timeout `notch-hook` is built around.
        let waits: Bool
    }

    static func configURL(_ agent: AgentKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = agent == .claude ? ".claude/settings.json" : ".codex/hooks.json"
        // Resolve links so a dotfiles symlink keeps pointing at the real file after we write.
        return home.appending(path: path).resolvingSymlinksInPath()
    }

    /// Each agent makes its settings folder (~/.claude, ~/.codex) the first time it runs.
    static func isInstalled(_ agent: AgentKind) -> Bool {
        FileManager.default.fileExists(atPath: configURL(agent).deletingLastPathComponent().path)
    }

    static func isConnected(_ agent: AgentKind) -> Bool {
        guard let command = try? command(agent),
              let hooks = (try? load(configURL(agent)))?["hooks"] as? [String: Any] else { return false }
        return events(agent).allSatisfy { event in
            (hooks[event.name] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
            }
        }
    }

    /// Replaces any older NotchApp entries (say, from a copy that has since moved) with fresh ones.
    static func connect(_ agent: AgentKind) throws {
        let command = try command(agent)
        try update(agent) { hooks in
            for event in events(agent) {
                var entry: [String: Any] = ["type": "command", "command": command]
                if event.waits { entry["timeout"] = 300 }
                var group: [String: Any] = ["hooks": [entry]]
                if let matcher = event.matcher { group["matcher"] = matcher }
                hooks[event.name] = try groups(hooks, event.name) + [group]
            }
        }
    }

    static func disconnect(_ agent: AgentKind) throws {
        try update(agent) { _ in }
    }

    private static func events(_ agent: AgentKind) -> [Event] {
        var events = [Event(name: "PermissionRequest", matcher: "*", waits: true)]
        // Codex has no question tool to intercept yet.
        if agent == .claude { events.append(Event(name: "PreToolUse", matcher: "AskUserQuestion", waits: true)) }
        for name in ["Stop", "UserPromptSubmit", "SessionEnd"] {
            events.append(Event(name: name, matcher: nil, waits: false))
        }
        return events
    }

    private static func command(_ agent: AgentKind) throws -> String {
        guard let path = Bundle.main.path(forAuxiliaryExecutable: "notch-hook") else {
            throw SetupError(errorDescription: "This copy of NotchApp is missing its notch-hook helper.")
        }
        // A copy opened straight from the disk image or Downloads runs from a temporary path
        // that disappears, which would leave the agents pointing at nothing.
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") {
            throw SetupError(errorDescription: "Move NotchApp to your Applications folder, open it from there, and connect again.")
        }
        let quoted = path.contains(" ") ? "'\(path)'" : path
        return "\(quoted) \(agent.rawValue)"
    }

    /// Strips NotchApp's entries from every event, lets `change` add new ones, and saves.
    private static func update(_ agent: AgentKind, _ change: (inout [String: Any]) throws -> Void) throws {
        let url = configURL(agent)
        var config = try load(url)
        guard config["hooks"] == nil || config["hooks"] is [String: Any] else {
            throw SetupError(errorDescription: "\"hooks\" in \(url.path) isn't an object, so NotchLab left the file alone.")
        }
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        for name in hooks.keys {
            let kept = try groups(hooks, name)
            hooks[name] = kept.isEmpty ? nil : kept
        }
        try change(&hooks)
        config["hooks"] = hooks.isEmpty ? nil : hooks
        try save(config, to: url)
    }

    /// The event's hook groups with NotchApp's own commands taken out.
    private static func groups(_ hooks: [String: Any], _ name: String) throws -> [[String: Any]] {
        guard hooks[name] == nil || hooks[name] is [[String: Any]] else {
            throw SetupError(errorDescription: "The \(name) hooks aren't in the expected format, so NotchLab left the file alone.")
        }
        return (hooks[name] as? [[String: Any]] ?? []).compactMap { group in
            guard let entries = group["hooks"] as? [[String: Any]] else { return group }
            let kept = entries.filter { !(($0["command"] as? String ?? "").contains("/notch-hook")) }
            if kept.count == entries.count { return group }
            if kept.isEmpty { return nil }
            var group = group
            group["hooks"] = kept
            return group
        }
    }

    private static func load(_ url: URL) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: url.path),
              !String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) else { return [:] }
        guard let config = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SetupError(errorDescription: "\(url.path) isn't valid JSON, so NotchLab left it alone. Fix it and try again.")
        }
        return config
    }

    private static func save(_ config: [String: Any], to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the user's original once, before NotchLab first touches the file.
        let backup = url.appendingPathExtension("before-notchapp")
        if manager.fileExists(atPath: url.path), !manager.fileExists(atPath: backup.path) {
            try manager.copyItem(at: url, to: backup)
        }
        // Settings can hold API keys, so the rewritten file keeps the original's permissions.
        let permissions = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions] ?? 0o600
        var data = try JSONSerialization.data(withJSONObject: config,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
