import SwiftUI

struct DevView: View {
    let model: NotchModel

    var body: some View {
        // A ZStack (not Group) so the lifecycle modifiers below attach once to the page,
        // rather than to each branch, which would stop sampling when a detail opens.
        ZStack {
            if let kind = model.statDetail {
                StatDetailView(kind: kind, system: model.system) { model.statDetail = nil }
            } else {
                VStack(spacing: 10) {
                    // An agent waiting on you takes the top spot until it's answered.
                    if let request = model.agents.requests.first {
                        AgentRequestCard(request: request, monitor: model.agents)
                            .frame(height: 160)
                    } else {
                        HStack(spacing: 10) {
                            UsageCard(title: "Claude", usage: model.usage.claude)
                            UsageCard(title: "Codex", usage: model.usage.codex)
                        }
                        .frame(height: 160)
                    }
                    HStack(spacing: 10) {
                        CompactStats(system: model.system) { model.statDetail = $0 }
                            .frame(width: 200)
                        AgentSessionsCard(monitor: model.agents)
                    }
                }
            }
        }
        .onAppear { model.system.start() }
        .onDisappear { model.system.stop() }
        .onChange(of: model.statDetail) { _, kind in model.system.showDetail(kind) }
        .task {
            model.usage.refreshIfStale()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { model.usage.refresh() }
            }
        }
    }
}

// MARK: Usage

struct UsageCard: View {
    let title: String
    let usage: ProviderUsage

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    if let plan = usage.plan {
                        Text(plan)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    Spacer()
                    if let note = usage.note {
                        Text(note)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                if usage.loaded {
                    LimitRow(title: "Session", window: usage.session)
                    LimitRow(title: "Week", window: usage.week)
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        TokenStat(title: "Today", totals: usage.today)
                        TokenStat(title: "7 days", totals: usage.last7Days)
                    }
                } else {
                    Spacer()
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    Spacer()
                }
            }
        }
    }
}

struct LimitRow: View {
    let title: String
    let window: LimitWindow?

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(resetText).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(color).frame(width: max(5, geometry.size.width * fraction))
                }
            }
            .frame(height: 5)
            HStack {
                Text(window.map { "\(Int($0.usedPercent.rounded()))% used" } ?? "—")
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(window.map { "\(Int((100 - $0.usedPercent).rounded()))% left" } ?? "")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
    }

    private var fraction: Double { min(max((window?.usedPercent ?? 0) / 100, 0), 1) }

    private var color: Color {
        let used = window?.usedPercent ?? 0
        if used >= 90 { return .red }
        if used >= 70 { return .orange }
        return Color(red: 0.25, green: 0.55, blue: 1)
    }

    private var resetText: String {
        guard let window else { return "unavailable" }
        guard let resetsAt = window.resetsAt else { return window.usedPercent == 0 ? "not started" : "" }
        let seconds = max(0, Int(resetsAt.timeIntervalSinceNow))
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}

struct TokenStat: View {
    let title: String
    let totals: TokenTotals

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text(formatTokens(totals.tokens)).font(.system(size: 12, weight: .bold).monospacedDigit())
            Text(costText).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
        }
        .help("Tokens including cache reads; cost is the API-equivalent estimate")
    }

    private var costText: String {
        if totals.unpriced && totals.cost == 0 { return "—" }
        return String(format: "$%.2f", totals.cost) + (totals.unpriced ? "+" : "")
    }
}

func formatTokens(_ count: Int) -> String {
    switch count {
    case 1_000_000_000...: String(format: "%.1fB", Double(count) / 1_000_000_000)
    case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...: String(format: "%.1fK", Double(count) / 1_000)
    default: "\(count)"
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

// MARK: System stats

/// CPU, memory and GPU at a glance; click one for its details.
struct CompactStats: View {
    let system: SystemMonitor
    let open: (StatKind) -> Void

    var body: some View {
        Card(padding: 8) {
            HStack(spacing: 0) {
                ForEach(StatKind.allCases) { kind in
                    Button { open(kind) } label: {
                        StatRing(kind: kind, value: value(kind)).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .help(kind.title)
                    .accessibilityLabel("\(kind.title) details")
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func value(_ kind: StatKind) -> Double {
        switch kind {
        case .cpu: system.cpu.usage
        case .memory: system.memory.percent
        case .gpu: system.gpu.usage
        }
    }
}

/// iPhone Batteries-widget style: a ring that fills with the percentage, the icon inside.
struct StatRing: View {
    let kind: StatKind
    let value: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(kind.color.opacity(0.22), lineWidth: 4.5)
                Circle()
                    .trim(from: 0, to: min(max(value / 100, 0.02), 1))
                    .stroke(kind.color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 42, height: 42)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
        }
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct StatDetailView: View {
    let kind: StatKind
    let system: SystemMonitor
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(kind.title) Overview").font(.system(size: 13, weight: .bold))
                    HStack(spacing: 14) {
                        Ring(value: overviewValue / 100, color: kind.color, label: String(format: "%.1f%%", overviewValue))
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(summaryRows, id: \.0) { row in DetailRow(label: row.0, value: row.1, color: kind.color) }
                        }
                    }
                    Divider().overlay(.white.opacity(0.1))
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(breakdownRows, id: \.0) { row in DetailRow(label: row.0, value: row.1, color: kind.color.opacity(0.6)) }
                    }
                }
            }
            .frame(width: 270)

            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top Processes").font(.system(size: 13, weight: .bold))
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close details")
                    }
                    if system.processes.isEmpty {
                        Spacer()
                        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(system.processes) { process in
                                    ProcessRow(process: process, kind: kind, totalMemory: system.memory.total)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var overviewValue: Double {
        switch kind {
        case .cpu: system.cpu.usage
        case .memory: system.memory.percent
        case .gpu: system.gpu.usage
        }
    }

    private var summaryRows: [(String, String)] {
        switch kind {
        case .cpu:
            return [("User", String(format: "%.1f%%", system.cpu.user)),
                    ("System", String(format: "%.1f%%", system.cpu.system)),
                    ("Idle", String(format: "%.1f%%", max(0, 100 - system.cpu.usage)))]
        case .memory:
            return [("Used", formatBytes(system.memory.used)),
                    ("Free", formatBytes(system.memory.free)),
                    ("Total", formatBytes(system.memory.total))]
        case .gpu:
            return [("Device", String(format: "%.0f%%", system.gpu.usage)),
                    ("Renderer", String(format: "%.0f%%", system.gpu.renderer)),
                    ("Tiler", String(format: "%.0f%%", system.gpu.tiler))]
        }
    }

    private var breakdownRows: [(String, String)] {
        switch kind {
        case .cpu:
            var load = [Double](repeating: 0, count: 3)
            getloadavg(&load, 3)
            return [("Load average", String(format: "%.2f  %.2f  %.2f", load[0], load[1], load[2])),
                    ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)")]
        case .memory:
            let memory = system.memory
            func share(_ bytes: UInt64) -> String {
                formatBytes(bytes) + String(format: " · %.0f%%", Double(bytes) / Double(max(memory.total, 1)) * 100)
            }
            return [("App", share(memory.app)), ("Wired", share(memory.wired)), ("Compressed", share(memory.compressed)),
                    ("Cached", share(memory.cached)), ("Swap used", formatBytes(memory.swapUsed))]
        case .gpu:
            return [("GPU memory in use", formatBytes(system.gpu.memoryInUse))]
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(.white.opacity(0.9))
        }
        .font(.system(size: 11, weight: .medium))
    }
}

struct Ring: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(value, 0.005), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            Text(label).font(.system(size: 15, weight: .bold).monospacedDigit())
        }
    }
}

struct ProcessRow: View {
    let process: ProcessUsage
    let kind: StatKind
    let totalMemory: UInt64

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: process.icon)
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if kind == .memory {
                    Text(formatBytes(UInt64(process.value)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer()
            Text(valueText)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(kind.color)
        }
        .padding(.vertical, 5)
    }

    private var valueText: String {
        switch kind {
        case .memory: String(format: "%.1f%%", process.value / Double(max(totalMemory, 1)) * 100)
        case .cpu, .gpu: String(format: "%.1f%%", process.value)
        }
    }
}
