import SwiftUI

struct AgentIcon: View {
    let agent: AgentKind
    var size: CGFloat = 16

    var body: some View {
        if let icon = agent.icon {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: agent == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundStyle(agent.color)
                .frame(width: size, height: size)
        }
    }
}

/// Takes over the top of the Dev page while an agent is waiting on you.
struct AgentRequestCard: View {
    let request: AgentRequest
    let monitor: AgentMonitor

    var body: some View {
        Card(padding: 10) {
            switch request.kind {
            case .permission(let tool, let summary, let detail):
                PermissionView(request: request, monitor: monitor, tool: tool, summary: summary, detail: detail)
            case .questions(let questions):
                QuestionsView(request: request, monitor: monitor, questions: questions)
                    .id(request.id)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder((request.isQuestion ? Color(red: 0.35, green: 0.62, blue: 1) : .orange).opacity(0.5), lineWidth: 1))
    }
}

private struct RequestHeader<Trailing: View>: View {
    let request: AgentRequest
    let monitor: AgentMonitor
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            AgentIcon(agent: request.agent)
            Text(request.agent.name).font(.system(size: 12, weight: .bold))
            Text("· \(request.project)").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            if monitor.requests.count > 1 {
                Text("+\(monitor.requests.count - 1) more")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
            Spacer(minLength: 6)
            Button("Terminal") { monitor.answerInTerminal(request) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .help("Answer in the terminal instead")
            trailing
        }
        .lineLimit(1)
        .frame(height: 20)
    }
}

private struct PermissionView: View {
    let request: AgentRequest
    let monitor: AgentMonitor
    let tool: String
    let summary: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RequestHeader(request: request, monitor: monitor, title: "wants to use \(tool)") {
                actionButton("Deny", fill: .white.opacity(0.14)) { monitor.deny(request) }
                actionButton("Allow", fill: .green) { monitor.allow(request) }
            }
            Text(summary)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            ScrollView {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .scrollIndicators(.never)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35)))
        }
    }
}

private struct QuestionsView: View {
    let request: AgentRequest
    let monitor: AgentMonitor
    let questions: [AgentQuestion]
    @State private var step = 0
    @State private var picks: [Int: Set<String>] = [:]

    private var question: AgentQuestion { questions[min(step, questions.count - 1)] }
    private var isLast: Bool { step >= questions.count - 1 }
    private var answered: Bool { !(picks[question.id] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RequestHeader(request: request, monitor: monitor,
                          title: questions.count > 1 ? "asks · \(step + 1) of \(questions.count)" : "asks") {
                if step > 0 {
                    actionButton("Back", fill: .white.opacity(0.14)) { step -= 1 }
                }
                actionButton(isLast ? "Send" : "Next", fill: answered ? Color(red: 0.35, green: 0.62, blue: 1) : .white.opacity(0.1)) {
                    advance()
                }
                .disabled(!answered)
            }
            Text(question.text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(question.options, id: \.self) { option in
                    optionButton(option)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func optionButton(_ option: AgentQuestion.Option) -> some View {
        let selected = picks[question.id]?.contains(option.label) == true
        return Button { pick(option) } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: question.multiSelect ? (selected ? "checkmark.square.fill" : "square")
                                                       : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color(red: 0.35, green: 0.62, blue: 1) : .white.opacity(0.4))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(selected ? 0.14 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.description)
        .accessibilityLabel(option.label)
    }

    private func pick(_ option: AgentQuestion.Option) {
        var chosen = picks[question.id] ?? []
        if question.multiSelect {
            if chosen.contains(option.label) { chosen.remove(option.label) } else { chosen.insert(option.label) }
        } else {
            chosen = [option.label]
        }
        picks[question.id] = chosen
    }

    private func advance() {
        guard answered else { return }
        if !isLast { step += 1; return }
        var answers: [String: String] = [:]
        for question in questions {
            // Keep the agent's option order rather than click order.
            let labels = question.options.map(\.label).filter { picks[question.id]?.contains($0) == true }
            answers[question.text] = labels.joined(separator: ", ")
        }
        monitor.answer(request, with: answers)
    }
}

private func actionButton(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Capsule().fill(fill))
    }
    .buttonStyle(PressableStyle())
}

/// Recent Claude Code / Codex sessions, in the space the stat cards used to take.
struct AgentSessionsCard: View {
    let monitor: AgentMonitor
    @State private var unconnected: [AgentKind] = []

    var body: some View {
        Card(padding: 8) {
            if monitor.sessions.isEmpty {
                VStack(spacing: 6) {
                    if unconnected.isEmpty {
                        HStack(spacing: 6) {
                            AgentIcon(agent: .claude, size: 14)
                            AgentIcon(agent: .codex, size: 14)
                        }
                    }
                    Text(unconnected.isEmpty ? "Claude and Codex questions show up here"
                                             : "Connect to answer agent questions here")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    if !unconnected.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(unconnected, id: \.self) { agent in
                                Button {
                                    setAgentHooks(agent, connected: true)
                                    refresh()
                                } label: {
                                    HStack(spacing: 5) {
                                        AgentIcon(agent: agent, size: 13)
                                        Text("Connect \(agent.name)").font(.system(size: 11, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 22)
                                    .background(Capsule().fill(.white.opacity(0.14)))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear(perform: refresh)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(monitor.sessions) { session in
                            SessionRow(session: session, monitor: monitor)
                        }
                    }
                }
            }
        }
    }

    private func refresh() {
        unconnected = [AgentKind.claude, .codex].filter { !AgentHooks.isConnected($0) }
    }
}

/// Connects or disconnects an agent's hooks, explaining anything the user still has to do.
@MainActor
func setAgentHooks(_ agent: AgentKind, connected: Bool) {
    do {
        if connected { try AgentHooks.connect(agent) } else { try AgentHooks.disconnect(agent) }
        // Codex won't run a new hook until the user reviews it, and NotchLab shouldn't skip that check.
        if connected, agent == .codex {
            showAlert("Codex is connected", "In Codex, run /hooks once and trust NotchLab's hooks. Codex sessions that are already open need a restart.")
        }
    } catch {
        showAlert("Couldn't \(connected ? "connect" : "disconnect") \(agent.name)", error.localizedDescription)
    }
}

@MainActor
private func showAlert(_ title: String, _ message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    // The notch never takes focus on its own, so bring the app forward or the alert opens behind.
    NSApp.activate()
    alert.runModal()
}

private struct SessionRow: View {
    let session: AgentSession
    let monitor: AgentMonitor
    @State private var hovering = false

    var body: some View {
        Button { monitor.open(app: session.app) } label: {
            HStack(spacing: 7) {
                AgentIcon(agent: session.agent, size: 14)
                Text(session.project)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering, session.status == .finished {
                    Button { monitor.dismiss(session) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Dismiss \(session.project)")
                } else {
                    Text(relativeTime(session.updated))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 21)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.lastMessage)
    }

    private var statusText: String {
        if let request = monitor.request(for: session) { return request.isQuestion ? "Asked a question" : "Needs approval" }
        if session.status == .working { return "Working…" }
        let firstLine = session.lastMessage.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Done" : firstLine
    }

    private var statusColor: Color {
        if monitor.request(for: session) != nil { return .orange }
        return session.status == .working ? Color(red: 0.35, green: 0.62, blue: 1) : .green
    }
}

/// Beside the closed notch while an agent waits on you, and briefly when a turn finishes.
struct AgentWings: View {
    let alert: AgentAlert
    let notchWidth: CGFloat
    let wing: CGFloat
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 0) {
            AgentIcon(agent: alert.agent, size: 18)
                .frame(width: wing)
            Spacer(minLength: notchWidth)
            HStack(spacing: 5) {
                Circle()
                    .fill(alert.color)
                    .frame(width: 6, height: 6)
                    .opacity(alert.pending && pulse ? 0.3 : 1)
                Text(alert.text)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(alert.color)
                    .lineLimit(1)
            }
            .frame(width: wing)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
