import Foundation

// Relays Claude Code and Codex hook events to NotchApp over a Unix socket.
// Permission requests and questions wait for the answer from the notch and print it for the
// agent. If NotchApp isn't running, or the notch hands the request back, nothing is printed
// and the agent shows its usual prompt in the terminal.

signal(SIGPIPE, SIG_IGN)

let agent = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "claude"
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { exit(0) }

let event = payload["hook_event_name"] as? String
let tool = payload["tool_name"] as? String
// A question the notch handed back goes to the terminal's own prompt, which raises a
// PermissionRequest for it; leave that one alone.
if event == "PermissionRequest", tool == "AskUserQuestion" { exit(0) }
let waitsForAnswer = event == "PermissionRequest" || (event == "PreToolUse" && tool == "AskUserQuestion")

let message: [String: Any] = [
    "agent": agent,
    // macOS sets this for processes started from an app (e.g. com.microsoft.VSCode),
    // so the notch can bring that app forward.
    "app": ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "",
    "payload": payload,
]
guard var data = try? JSONSerialization.data(withJSONObject: message) else { exit(0) }
data.append(UInt8(ascii: "\n"))

let socketPath = NSHomeDirectory() + "/Library/Application Support/NotchApp/agent.sock"
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { exit(0) }
withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { exit(0) }

let sent = data.withUnsafeBytes { buffer -> Bool in
    var offset = 0
    while offset < buffer.count {
        let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
        if written <= 0 { return false }
        offset += written
    }
    return true
}
guard sent, waitsForAnswer else { exit(0) }

// Give up a little before the hook's 300 s timeout so the agent falls back to its own
// prompt cleanly instead of reporting a timed-out hook.
var timeout = timeval(tv_sec: 290, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

var response = Data()
var chunk = [UInt8](repeating: 0, count: 16_384)
while response.last != UInt8(ascii: "\n") {
    let count = read(fd, &chunk, chunk.count)
    if count <= 0 { break }
    response.append(contentsOf: chunk[0..<count])
}
let answer = String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
if !answer.isEmpty { print(answer) }
