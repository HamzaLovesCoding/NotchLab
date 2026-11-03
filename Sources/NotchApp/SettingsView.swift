import AVFoundation
import EventKit
import ServiceManagement
import SwiftUI

private enum SettingsSection: String, CaseIterable {
    case connections = "Connections"
    case general = "General"
    case appearance = "Appearance"
    case home = "Home"
    case pages = "Pages"
    case agents = "Agents"
    case timer = "Focus Timer"
    case clipboard = "Clipboard & Files"

    var symbol: String {
        switch self {
        case .connections: "link"
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .home: "house.fill"
        case .pages: "square.grid.2x2.fill"
        case .agents: "sparkles"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard.fill"
        }
    }
}

/// Opened from the gear in the top bar; takes the place of the current page.
struct SettingsView: View {
    let model: NotchModel
    @State private var section = SettingsSection.connections

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases, id: \.self) { item in
                    SidebarButton(title: item.rawValue, symbol: item.symbol, selected: section == item) { section = item }
                }
                Spacer(minLength: 0)
                SidebarButton(title: "Quit NotchLab", symbol: "power", selected: false) { NSApp.terminate(nil) }
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.leading, 10)
                    .padding(.top, 2)
            }
            .frame(width: 164)

            Card(padding: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch section {
                        case .connections: ConnectionSettings(model: model)
                        case .general: GeneralSettings(settings: model.settings, tabs: model.visibleTabs)
                        case .appearance: AppearanceSettings(settings: model.settings)
                        case .home: HomeSettings(model: model)
                        case .pages: PageSettings(model: model)
                        case .agents: AgentSettings(settings: model.settings)
                        case .timer: TimerSettings(timer: model.focusTimer, settings: model.settings)
                        case .clipboard: ClipboardSettings(model: model)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}

// MARK: Sections

/// Everything NotchLab can hook into or needs permission for, in one place.
private struct ConnectionSettings: View {
    let model: NotchModel
    @State private var agents: Set<AgentKind> = []
    @State private var installed: Set<AgentKind> = []
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var reminders = EKEventStore.authorizationStatus(for: .reminder)
    @State private var calendar = EKEventStore.authorizationStatus(for: .event)
    @State private var accessibility = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var connecting = false

    var body: some View {
        let claude = model.usage.claude
        let signedIn = claude.note != ClaudeLimits.signedOutNote
        // An agent that isn't on this Mac doesn't count against "all connected".
        let agentsDone = [AgentKind.claude, .codex].filter { installed.contains($0) || agents.contains($0) }.map(agents.contains)
        let done = agentsDone + [camera == .authorized, reminders == .fullAccess, calendar == .fullAccess, accessibility, launchAtLogin]
        let allDone = !done.contains(false)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.showWelcome ? "Welcome to NotchLab" : "Connections")
                    .font(.system(size: 13, weight: .bold))
                Text(model.showWelcome ? "Connect what you'd like to use. You can change it here anytime."
                                       : "\(done.filter { $0 }.count) of \(done.count) connected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PillButton(title: allDone ? "All connected" : (connecting ? "Connecting…" : "Connect all"), action: connectAll)
                .disabled(allDone || connecting)
        }
        .frame(height: 44)
        RowDivider()
        agentRow(.claude, title: "Claude Code", detail: "Questions and approvals in the notch")
        RowDivider()
        agentRow(.codex, title: "Codex", detail: "Run /hooks in Codex once to trust it")
        RowDivider()
        SettingRow(title: "Claude usage", detail: signedIn ? "Session and weekly limits on the Dev page"
                                                            : "Run claude in Terminal and sign in", symbol: "chart.bar.fill") {
            if !claude.loaded {
                ProgressView().controlSize(.small)
            } else if signedIn {
                StatusBadge(title: "Connected")
            } else {
                PillButton(title: "Check again", action: model.usage.refresh)
            }
        }
        RowDivider()
        permissionRow("Camera", detail: "For the mirror on Home", symbol: "web.camera.fill",
                      granted: camera == .authorized, undecided: camera == .notDetermined, pane: "Privacy_Camera") {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refresh()
            }
        }
        RowDivider()
        permissionRow("Reminders", detail: "For the Reminders page", symbol: "checklist",
                      granted: reminders == .fullAccess, undecided: reminders == .notDetermined, pane: "Privacy_Reminders") {
            Task {
                await model.reminders.requestAccess().value
                refresh()
            }
        }
        RowDivider()
        permissionRow("Calendar", detail: "Your next meeting on Home and by the notch", symbol: "calendar",
                      granted: calendar == .fullAccess, undecided: calendar == .notDetermined, pane: "Privacy_Calendars") {
            Task {
                await model.meetings.requestAccess().value
                refresh()
            }
        }
        RowDivider()
        // macOS only offers the prompt; once dismissed, the switch lives in System Settings.
        permissionRow("VPN control", detail: "Lets the VPN switch work apps like ProtonVPN", symbol: "lock.shield.fill",
                      granted: accessibility, undecided: true, pane: "Privacy_Accessibility",
                      request: model.vpn.requestAppControlPermission)
        RowDivider()
        SettingRow(title: "Launch at login", detail: "Open NotchLab when you log in", symbol: "power") {
            SwitchView(isOn: launchAtLogin) { setLaunchAtLogin(!launchAtLogin) }
        }
        if model.showWelcome {
            HStack {
                Spacer()
                PillButton(title: "Done") { model.showSettings = false; model.showWelcome = false }
            }
            .padding(.top, 8)
        }
        Color.clear.frame(height: 0)
            .onAppear { model.usage.refreshIfStale() }
            // Permissions can change in System Settings while this page is open.
            .task {
                while !Task.isCancelled {
                    refresh()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    private func agentRow(_ agent: AgentKind, title: String, detail: String) -> some View {
        let isConnected = agents.contains(agent)
        let status = installed.contains(agent) ? "Not connected" : "Not installed on this Mac"
        return SettingRow(title: title, detail: isConnected ? detail : status, icon: agent) {
            SwitchView(isOn: isConnected) {
                setAgentHooks(agent, connected: !isConnected)
                refresh()
            }
        }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, undecided: Bool,
                               pane: String, request: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail, symbol: symbol) {
            if granted {
                StatusBadge(title: "Allowed")
            } else if undecided {
                PillButton(title: "Allow", action: request)
            } else {
                PillButton(title: "Open Settings") { openPrivacySettings(pane) }
            }
        }
    }

    private func refresh() {
        let connected = Set([AgentKind.claude, .codex].filter(AgentHooks.isConnected))
        if connected != agents { agents = connected }
        let found = Set([AgentKind.claude, .codex].filter(AgentHooks.isInstalled))
        if found != installed { installed = found }
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        reminders = EKEventStore.authorizationStatus(for: .reminder)
        calendar = EKEventStore.authorizationStatus(for: .event)
        accessibility = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Asks for each missing piece in turn, so macOS shows one prompt at a time.
    private func connectAll() {
        connecting = true
        Task {
            for agent in [AgentKind.claude, .codex] where AgentHooks.isInstalled(agent) && !AgentHooks.isConnected(agent) {
                setAgentHooks(agent, connected: true)
            }
            if SMAppService.mainApp.status != .enabled { setLaunchAtLogin(true) }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                await model.reminders.requestAccess().value
            }
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                await model.meetings.requestAccess().value
            }
            if !AXIsProcessTrusted() { model.vpn.requestAppControlPermission() }
            refresh()
            connecting = false
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct GeneralSettings: View {
    let settings: AppSettings
    let tabs: [NotchTab]

    var body: some View {
        SettingRow(title: "Open the notch", detail: settings.openOnClick ? "Click the notch to open it" : "Rest the pointer on the notch") {
            Choice(options: [("Hover", false), ("Click", true)], selection: settings.openOnClick) { settings.openOnClick = $0 }
        }
        if !settings.openOnClick {
            RowDivider()
            SettingRow(title: "Open after hovering", detail: "How long to rest on the notch") {
                Choice(options: [("Instant", 0.1), ("Short", 0.3), ("Long", 0.6)],
                       selection: settings.openDelay) { settings.openDelay = $0 }
            }
        }
        RowDivider()
        SettingRow(title: "Close after leaving", detail: "How long the panel waits for you") {
            Choice(options: [("Instant", 0.15), ("Short", 0.5), ("Long", 1.0)],
                   selection: settings.closeDelay) { settings.closeDelay = $0 }
        }
        RowDivider()
        SettingRow(title: "Open to", detail: "The page you see when the notch opens") {
            MenuButton(title: settings.startTab?.title ?? "Last page used") {
                [ActionMenuItem("Last page used", checked: settings.startTab == nil) { settings.startTab = nil }, .separator()]
                    + tabs.map { tab in
                        ActionMenuItem(tab.title, checked: settings.startTab == tab) { settings.startTab = tab }
                    }
            }
        }
    }
}

private struct AppearanceSettings: View {
    let settings: AppSettings

    var body: some View {
        SettingRow(title: "Accent color", detail: "Switches, the open tab, and highlights") {
            HStack(spacing: 6) {
                ForEach(AccentChoice.allCases, id: \.self) { choice in
                    AccentSwatch(choice: choice, selected: settings.accent == choice) { settings.accent = choice }
                }
            }
        }
        RowDivider()
        SettingRow(title: "Panel width", detail: "How wide the open notch gets") {
            Choice(options: [("Standard", 680.0), ("Wide", 760.0), ("Wider", 840.0)],
                   selection: settings.panelWidth) { settings.panelWidth = $0 }
        }
    }
}

private struct HomeSettings: View {
    let model: NotchModel

    var body: some View {
        let settings = model.settings
        SettingRow(title: "Music controls", detail: "What the player shows and controls") {
            MenuButton(title: settings.mediaSource.title) {
                MediaSource.allCases.map { source in
                    ActionMenuItem(source.title, checked: settings.mediaSource == source) { model.nowPlaying.setSource(source) }
                }
            }
        }
        RowDivider()
        cardRow(.music, detail: "Song, controls, and speaker picker")
        ForEach(settings.homeOrder, id: \.self) { card in
            RowDivider()
            let index = settings.homeOrder.firstIndex(of: card) ?? 0
            let place = index == 0 ? "Top" : index == settings.homeOrder.count - 1 ? "Bottom" : "Middle"
            let detail = card != .meeting ? "\(place) of the column beside the music"
                : model.meetings.hasAccess ? "\(place) of the column, and by the notch just before"
                : "Allow Calendar in Connections first"
            cardRow(card, detail: detail) {
                HStack(spacing: 0) {
                    moveButton("chevron.up", label: "Move \(card.title) up", enabled: index > 0) {
                        settings.moveColumnCard(card, by: -1)
                    }
                    moveButton("chevron.down", label: "Move \(card.title) down", enabled: index < settings.homeOrder.count - 1) {
                        settings.moveColumnCard(card, by: 1)
                    }
                }
            }
        }
        RowDivider()
        SettingRow(title: "Mirror button", detail: "The camera button on Home") {
            SwitchView(isOn: settings.showMirrorButton) {
                settings.showMirrorButton.toggle()
                if !settings.showMirrorButton { model.mirror.isOn = false }
            }
        }
        RowDivider()
        SettingRow(title: "Music beside the notch", detail: "Artwork and bars while something plays") {
            SwitchView(isOn: settings.showMusicWing) { settings.showMusicWing.toggle() }
        }
    }

    private func cardRow(_ card: HomeCard, detail: String,
                         @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        let shown = !model.settings.hiddenHomeCards.contains(card)
        return SettingRow(title: card.title, detail: detail) {
            HStack(spacing: 10) {
                extra()
                SwitchView(isOn: shown) {
                    if shown { model.settings.hiddenHomeCards.insert(card) } else { model.settings.hiddenHomeCards.remove(card) }
                }
            }
        }
    }

    private func moveButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 0.8 : 0.25)
        .accessibilityLabel(label)
    }
}

private struct PageSettings: View {
    let model: NotchModel

    var body: some View {
        pageRow(.shelf, detail: "A file shelf with AirDrop. Dragged files open it.")
        RowDivider()
        pageRow(.reminders, detail: "Your Apple Reminders lists")
        RowDivider()
        pageRow(.dev, detail: "Usage and sessions. Shows up anyway when an agent asks.")
        Text("ON THE DEV PAGE")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 14)
            .padding(.bottom, 2)
        devRow(.usage, detail: "Claude and Codex session and weekly limits")
        RowDivider()
        devRow(.stats, detail: "CPU, memory, and GPU")
        RowDivider()
        devRow(.sessions, detail: "Recent agent sessions and their status")
    }

    private func pageRow(_ tab: NotchTab, detail: String) -> some View {
        let shown = !model.settings.hiddenTabs.contains(tab)
        return SettingRow(title: tab.title, detail: detail) {
            SwitchView(isOn: shown) { model.setTab(tab, hidden: shown) }
        }
    }

    private func devRow(_ card: DevCard, detail: String) -> some View {
        let shown = !model.settings.hiddenDevCards.contains(card)
        return SettingRow(title: card.title, detail: detail) {
            SwitchView(isOn: shown) {
                if shown { model.settings.hiddenDevCards.insert(card) } else { model.settings.hiddenDevCards.remove(card) }
            }
        }
    }
}

private struct AgentSettings: View {
    let settings: AppSettings

    var body: some View {
        SettingRow(title: "Questions & approvals", detail: routingDetail) {
            Choice(options: [("Notch", PromptRouting.notch), ("Auto", .auto), ("Terminal", .terminal)],
                   selection: settings.promptRouting) { settings.promptRouting = $0 }
        }
        RowDivider()
        SettingRow(title: "Flash when an agent finishes", detail: "A green Done beside the closed notch") {
            SwitchView(isOn: settings.showFinishedAlert) { settings.showFinishedAlert.toggle() }
        }
        RowDivider()
        SettingRow(title: "Usage warnings", detail: "Flash at 80% and 95% of a Claude or Codex limit") {
            SwitchView(isOn: settings.usageWarnings) { settings.usageWarnings.toggle() }
        }
        Text("A question answered in the notch doesn't appear in the terminal or Remote Control. Auto keeps them in the notch while you're using the Mac, and sends them to the terminal once you've been away for 2 minutes. Connect Claude Code and Codex in Connections.")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private var routingDetail: String {
        switch settings.promptRouting {
        case .notch: "Always here; the terminal won't show them"
        case .auto: "Here at the Mac, terminal when you're away"
        case .terminal: "In the terminal and Remote Control"
        }
    }
}

private struct TimerSettings: View {
    let timer: FocusTimer
    let settings: AppSettings
    @State private var shortcuts: [String] = []
    private static let ranges = ["Focus": 5...120, "Break": 1...30, "Deep": 10...180]
    private static let sounds = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
        .map { ($0 as NSString).deletingPathExtension }
        .sorted()

    var body: some View {
        ForEach(FocusTimer.presets) { preset in
            SettingRow(title: preset.name, detail: preset.isBreak ? "Short rest between sessions" : nil) {
                MinutesStepper(value: timer.minutes(for: preset), range: Self.ranges[preset.name] ?? 1...180,
                               step: preset.isBreak ? 1 : 5) { timer.setMinutes($0, for: preset) }
            }
            RowDivider()
        }
        ForEach(settings.customPresets) { custom in
            CustomPresetRow(timer: timer, settings: settings, custom: custom)
            RowDivider()
        }
        SettingRow(title: "Your presets", detail: "Like debate speeches; prep time can keep what's left") {
            PillButton(title: "Add preset") {
                settings.customPresets.append(CustomPreset(name: "Preset \(settings.customPresets.count + 1)", minutes: 5))
            }
        }
        RowDivider()
        SettingRow(title: "When a countdown starts", detail: "Run a Shortcut, like one that turns on a Focus") {
            shortcutMenu(settings.focusStartShortcut) { settings.focusStartShortcut = $0 }
        }
        RowDivider()
        SettingRow(title: "When it ends or resets", detail: "Breaks don't run either Shortcut") {
            shortcutMenu(settings.focusEndShortcut) { settings.focusEndShortcut = $0 }
        }
        RowDivider()
        SettingRow(title: "Sound when done", detail: "Plays when a countdown ends") {
            MenuButton(title: settings.timerSound.isEmpty ? "None" : settings.timerSound) {
                [ActionMenuItem("None", checked: settings.timerSound.isEmpty) { settings.timerSound = "" }, .separator()]
                    + Self.sounds.map { name in
                        ActionMenuItem(name, checked: settings.timerSound == name) {
                            settings.timerSound = name
                            NSSound(named: name)?.play()
                        }
                    }
            }
        }
        RowDivider()
        SettingRow(title: "Celebration", detail: "Confetti and a check beside the notch") {
            SwitchView(isOn: settings.timerCelebration) { settings.timerCelebration.toggle() }
        }
        .task { shortcuts = await Task.detached { FocusTimer.shortcutNames() }.value }
    }

    private func shortcutMenu(_ current: String, set: @escaping (String) -> Void) -> some View {
        MenuButton(title: current.isEmpty ? "None" : current) {
            var items: [NSMenuItem] = [ActionMenuItem("None", checked: current.isEmpty) { set("") }, .separator()]
            if shortcuts.isEmpty {
                let none = NSMenuItem(title: "No shortcuts in the Shortcuts app", action: nil, keyEquivalent: "")
                none.isEnabled = false
                items.append(none)
            }
            return items + shortcuts.map { name in ActionMenuItem(name, checked: current == name) { set(name) } }
        }
    }
}

/// A preset added in Settings: its name, whether it keeps leftover time, and its length.
private struct CustomPresetRow: View {
    let timer: FocusTimer
    let settings: AppSettings
    let custom: CustomPreset

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: Binding(get: { custom.name }, set: { name in update { $0.name = name } }))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
            Text("Keep leftover")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize()
            SwitchView(isOn: custom.bank) { update { $0.bank.toggle() } }
                .help("Like a prep-time bank: pick it again to carry on where you left off")
                .accessibilityLabel("Keep leftover time")
            MinutesStepper(value: custom.minutes, range: 1...180, step: 1) {
                timer.setMinutes($0, for: TimerPreset(custom: custom))
            }
            Button { timer.remove(custom) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Delete \(custom.name)")
        }
        .frame(height: 40)
    }

    private func update(_ change: (inout CustomPreset) -> Void) {
        guard let index = settings.customPresets.firstIndex(where: { $0.id == custom.id }) else { return }
        change(&settings.customPresets[index])
    }
}

private struct ClipboardSettings: View {
    let model: NotchModel

    var body: some View {
        let settings = model.settings
        let clipCount = model.clipboard.items.filter { !$0.favorite }.count
        SettingRow(title: "Keep in history", detail: "Favorites are always kept") {
            Choice(options: [("25", 25), ("50", 50), ("100", 100), ("200", 200)], selection: settings.clipboardLimit) {
                settings.clipboardLimit = $0
                model.clipboard.applyLimit()
            }
        }
        RowDivider()
        SettingRow(title: "Pause history", detail: "Nothing you copy is saved while paused") {
            SwitchView(isOn: settings.clipboardPaused) { settings.clipboardPaused.toggle() }
        }
        RowDivider()
        SettingRow(title: "Clear clipboard history", detail: "\(clipCount) \(clipCount == 1 ? "item" : "items") · favorites stay") {
            PillButton(title: "Clear", action: model.clipboard.clearHistory).disabled(clipCount == 0)
        }
        RowDivider()
        let fileCount = model.shelf.items.count
        SettingRow(title: "Clear file shelf", detail: "\(fileCount) \(fileCount == 1 ? "file" : "files") on the shelf") {
            PillButton(title: "Clear", action: model.shelf.clear).disabled(fileCount == 0)
        }
    }
}

// MARK: Controls

private struct SidebarButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(selected ? 1 : (hovering ? 0.8 : 0.55)))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(selected ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var icon: AgentKind?
    var symbol: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            if let icon { AgentIcon(agent: icon, size: 18) }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .frame(height: 40)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
    }
}

/// A small segmented control in the notch's style.
private struct Choice<Value: Equatable>: View {
    let options: [(label: String, value: Value)]
    let selection: Value
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { select(option.value) } label: {
                    Text(option.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(.white.opacity(selected ? 0.2 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
    }
}

private struct MenuButton: View {
    let title: String
    let items: () -> [NSMenuItem]

    var body: some View {
        Button { popUpMenu(items()) } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: 150)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MinutesStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Shorter", enabled: value > range.lowerBound) {
                set(max(range.lowerBound, value - step))
            }
            Text("\(value) min")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 52)
            stepButton("plus", label: "Longer", enabled: value < range.upperBound) {
                set(min(range.upperBound, value + step))
            }
        }
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct StatusBadge: View {
    let title: String
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent ?? .green)
            Text(title).foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

private struct AccentSwatch: View {
    let choice: AccentChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let color = choice.color {
                    Circle().fill(color)
                } else {
                    // The built-in look mixes green switches with blue highlights.
                    Circle().fill(LinearGradient(colors: [.green, .notchBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .frame(width: 16, height: 16)
            .padding(2)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(choice == .standard ? "Default" : choice.rawValue.capitalized)
        .accessibilityLabel(choice == .standard ? "Default" : choice.rawValue.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
