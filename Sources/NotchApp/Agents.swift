import AppKit
import Observation
import SwiftUI

enum AgentKind: String {
    case claude, codex

    var name: String { self == .claude ? "Claude" : "Codex" }
    var color: Color { self == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : .white }

    /// The desktop app's icon, when installed, stands in for the agent's logo.
    var icon: NSImage? {
        let bundleID = self == .claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct AgentQuestion: Identifiable {
    struct Option: Hashable {
        let label: String
        let description: String
    }

    let id: Int
    let text: String
    let header: String
    let options: [Option]
    let multiSelect: Bool
}

/// An agent blocked on the user. The hook process stays connected until it gets an answer.
struct AgentRequest: Identifiable {
    enum Kind {
        case permission(tool: String, summary: String, detail: String)
        case questions([AgentQuestion])
    }

    let id = UUID()
    let agent: AgentKind
    let sessionKey: String
    let project: String
    let app: String
    let kind: Kind
    fileprivate let connection: Int32
    /// The question tool's original input, echoed back with the answers added.
    fileprivate let toolInput: [String: Any]

    var isQuestion: Bool { if case .questions = kind { true } else { false } }
}

struct AgentSession: Identifiable {
    enum Status { case working, finished }

    let id: String
    let agent: AgentKind
    var project: String
    var app: String
    var status: Status
    var lastMessage = ""
    var updated = Date()
}

struct AgentAlert: Equatable {
    let agent: AgentKind
    let text: String
    let color: Color
    let pending: Bool
}

/// Receives Claude Code / Codex hook events from `notch-hook` (see Sources/NotchHook).
@Observable
@MainActor
final class AgentMonitor {
    private(set) var requests: [AgentRequest] = []
    private(set) var sessions: [AgentSession] = []
    /// Set for a few seconds after a turn finishes, for the side alert on the closed notch.
    private(set) var justFinished: AgentSession?
    @ObservationIgnored var onRequest: (() -> Void)?
    @ObservationIgnored private var server: AgentSocketServer?

    static let socketPath = NSHomeDirectory() + "/Library/Application Support/NotchApp/agent.sock"

    func start() {
        guard server == nil else { return }
        try? FileManager.default.createDirectory(atPath: (Self.socketPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        server = AgentSocketServer(path: Self.socketPath,
                                   onMessage: { [weak self] data, fd in self?.handle(data, from: fd) ?? false },
                                   onClose: { [weak self] fd in self?.requests.removeAll { $0.connection == fd } })
    }

    var alert: AgentAlert? {
        if let request = requests.first {
            return AgentAlert(agent: request.agent, text: request.isQuestion ? "Question" : "Approve?",
                              color: request.isQuestion ? Color(red: 0.35, green: 0.62, blue: 1) : .orange, pending: true)
        }
        if let session = justFinished {
            return AgentAlert(agent: session.agent, text: "Done", color: .green, pending: false)
        }
        return nil
    }

    func request(for session: AgentSession) -> AgentRequest? { requests.first { $0.sessionKey == session.id } }

    // MARK: Answers

    func allow(_ request: AgentRequest) {
        respond(request, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]])
    }

    func deny(_ request: AgentRequest) {
        respond(request, ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                 "decision": ["behavior": "deny", "message": "Denied from the notch."]]])
    }

    /// `answers` maps question text to the chosen label(s), comma-joined for multi-select.
    func answer(_ request: AgentRequest, with answers: [String: String]) {
        var input = request.toolInput
        input["answers"] = answers
        respond(request, ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                 "updatedInput": input]])
    }

    /// Hands the request back so the agent shows its own prompt, then brings that app forward.
    func answerInTerminal(_ request: AgentRequest) {
        respond(request, nil)
        open(app: request.app)
    }

    func open(app: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.activate()
    }

    func dismiss(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
    }

    private func respond(_ request: AgentRequest, _ object: [String: Any]?) {
        var data = object.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        data.append(UInt8(ascii: "\n"))
        requests.removeAll { $0.id == request.id }
        server?.reply(data, to: request.connection)
        updateSession(request.sessionKey) { $0.status = .working }
    }

    // MARK: Events

    /// Returns true to keep the connection open while the hook waits for an answer.
    private func handle(_ data: Data, from fd: Int32) -> Bool {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = message["payload"] as? [String: Any],
              let event = payload["hook_event_name"] as? String else { return false }
        let agent = AgentKind(rawValue: message["agent"] as? String ?? "") ?? .claude
        let key = agent.rawValue + ":" + (payload["session_id"] as? String ?? "")
        let cwd = payload["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? agent.name : (cwd as NSString).lastPathComponent
        let app = message["app"] as? String ?? ""
        let tool = payload["tool_name"] as? String ?? ""
        let input = payload["tool_input"] as? [String: Any] ?? [:]

        if !sessions.contains(where: { $0.id == key }) {
            sessions.insert(AgentSession(id: key, agent: agent, project: project, app: app, status: .working), at: 0)
        }

        switch event {
        case "PermissionRequest":
            let (summary, detail) = Self.describe(tool: tool, input: input)
            add(AgentRequest(agent: agent, sessionKey: key, project: project, app: app,
                             kind: .permission(tool: tool, summary: summary, detail: detail), connection: fd, toolInput: [:]))
            return true
        case "PreToolUse" where tool == "AskUserQuestion":
            let questions = Self.parseQuestions(input["questions"])
            guard !questions.isEmpty else { return false }
            add(AgentRequest(agent: agent, sessionKey: key, project: project, app: app,
                             kind: .questions(questions), connection: fd, toolInput: input))
            return true
        case "UserPromptSubmit":
            updateSession(key) { $0.status = .working; $0.lastMessage = "" }
        case "Stop":
            updateSession(key) {
                $0.status = .finished
                $0.lastMessage = (payload["last_assistant_message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            justFinished = sessions.first { $0.id == key }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.justFinished?.id == key { self?.justFinished = nil }
            }
        case "SessionEnd":
            sessions.removeAll { $0.id == key }
        default:
            break
        }
        return false
    }

    private func add(_ request: AgentRequest) {
        requests.append(request)
        updateSession(request.sessionKey) { _ in }
        onRequest?()
    }

    private func updateSession(_ key: String, _ change: (inout AgentSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == key }) else { return }
        change(&sessions[index])
        sessions[index].updated = Date()
        sessions.sort { $0.updated > $1.updated }
    }

    /// A one-line summary and the exact command or target to show under it.
    private static func describe(tool: String, input: [String: Any]) -> (String, String) {
        let description = input["description"] as? String ?? ""
        if let command = input["command"] as? String ?? input["cmd"] as? String {
            return (description.isEmpty ? "Run a command" : description, command)
        }
        if let parts = input["command"] as? [String] {
            return (description.isEmpty ? "Run a command" : description, parts.joined(separator: " "))
        }
        if let path = input["file_path"] as? String {
            return ("\(tool) \((path as NSString).lastPathComponent)", path)
        }
        if let url = input["url"] as? String { return ("Fetch a web page", url) }
        if let plan = input["plan"] as? String { return ("Approve the plan", plan) }
        if let patch = input["input"] as? String ?? input["patch"] as? String { return ("Apply a patch", patch) }
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (description.isEmpty ? "Use \(tool)" : description, String(json.prefix(600)))
    }

    private static func parseQuestions(_ value: Any?) -> [AgentQuestion] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.enumerated().compactMap { index, item in
            guard let text = item["question"] as? String,
                  let options = item["options"] as? [[String: Any]], !options.isEmpty else { return nil }
            return AgentQuestion(id: index, text: text, header: item["header"] as? String ?? "",
                                 options: options.compactMap { option in
                                     (option["label"] as? String).map {
                                         AgentQuestion.Option(label: $0, description: option["description"] as? String ?? "")
                                     }
                                 },
                                 multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }
}

/// Unix domain socket server on the main queue. Each client sends one newline-terminated
/// JSON message; clients waiting for an answer stay connected until `reply` or they hang up.
@MainActor
final class AgentSocketServer {
    private struct Client {
        let source: DispatchSourceRead
        var buffer = Data()
        var delivered = false
    }

    private let listenFD: Int32
    private let acceptSource: DispatchSourceRead
    private var clients: [Int32: Client] = [:]
    private let onMessage: (Data, Int32) -> Bool
    private let onClose: (Int32) -> Void

    init?(path: String, onMessage: @escaping (Data, Int32) -> Bool, onClose: @escaping (Int32) -> Void) {
        self.onMessage = onMessage
        self.onClose = onClose
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // Owner-only, so other accounts on the Mac can't post fake prompts.
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { close(fd); return nil }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        listenFD = fd
        acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        acceptSource.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.acceptClients() } }
        acceptSource.resume()
    }

    /// Sends the answer (blocking, since the hook is reading) and hangs up.
    func reply(_ data: Data, to fd: Int32) {
        guard clients[fd] != nil else { return }
        _ = fcntl(fd, F_SETFL, 0)
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
        drop(fd)
    }

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            // A hook that already exited must not kill the app with SIGPIPE when answered.
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read(fd) } }
            source.setCancelHandler { close(fd) }
            clients[fd] = Client(source: source)
            source.resume()
        }
    }

    private func read(_ fd: Int32) {
        guard var client = clients[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count < 0, errno == EAGAIN { return }
        guard count > 0 else {
            let wasWaiting = client.delivered
            drop(fd)
            if wasWaiting { onClose(fd) }
            return
        }
        guard !client.delivered else { return }
        client.buffer.append(contentsOf: chunk[0..<count])
        guard let newline = client.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            if client.buffer.count > 8_000_000 { drop(fd) } else { clients[fd] = client }
            return
        }
        client.delivered = true
        clients[fd] = client
        if !onMessage(client.buffer[..<newline], fd) { drop(fd) }
    }

    private func drop(_ fd: Int32) {
        clients.removeValue(forKey: fd)?.source.cancel()
    }
}
