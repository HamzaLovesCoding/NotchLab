import AppKit
import Observation

enum NotchTab: String, CaseIterable {
    case home, shelf, reminders, dev

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Files"
        case .reminders: "Reminders"
        case .dev: "Dev"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .reminders: "checklist"
        case .dev: "terminal.fill"
        }
    }
}

enum DropTarget { case shelf, airDrop }

/// What shows beside the closed notch.
enum NotchActivity {
    case celebration
    case agent(AgentAlert)
    case usage(UsageWarning)
    case meeting(Meeting)
    case music

    /// Width of each side.
    var wing: CGFloat {
        switch self {
        case .celebration: 64
        case .agent, .usage, .meeting: 88
        case .music: 40
        }
    }
}

/// UI state shared between the AppKit window controller and the SwiftUI views.
@Observable
@MainActor
final class NotchModel {
    var isExpanded = false
    var tab: NotchTab = .home
    var statDetail: StatKind?
    var showClipboard = false
    var showSettings = false {
        didSet { if !showSettings { showWelcome = false } }
    }
    /// The first time the notch opens, Settings shows Connections with a welcome line.
    var showWelcome = false
    var notchSize = CGSize(width: 200, height: 32)

    /// Highlighted drop zone while a file drag hovers the panel.
    var dropTarget: DropTarget?
    /// AirDrop tile frame in the hosting view's (top-left origin) space, used to route drops.
    var airDropFrame: CGRect = .zero

    let nowPlaying: NowPlaying
    let audioOutputs = AudioOutputs()
    let settings: AppSettings
    let focusTimer: FocusTimer
    let mirror = Mirror()
    let notes = NotesStore()
    let vpn = VPNController()
    let clipboard: ClipboardHistory
    let shelf = Shelf()
    let reminders = RemindersStore()
    let usage: UsageStore
    let system = SystemMonitor()
    let agents: AgentMonitor
    let meetings = MeetingsStore()

    init() {
        let settings = AppSettings()
        self.settings = settings
        agents = AgentMonitor(settings: settings)
        nowPlaying = NowPlaying(settings: settings)
        focusTimer = FocusTimer(settings: settings)
        clipboard = ClipboardHistory(settings: settings)
        usage = UsageStore(settings: settings)
        tab = settings.startTab ?? .home
        // The next hover should land on the request, so switch pages while the notch is closed.
        agents.onRequest = { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.resetOverlays()
            self.tab = .dev
        }
    }

    /// Vertical padding around page content (6 above, 14 below).
    static let pagePadding: CGFloat = 20
    /// Questions get more room than approvals for the typed-answer field.
    static let questionHeight: CGFloat = 200
    private static let clipboardArea: CGFloat = 330

    /// Tabs shown in the top bar. Dev comes back while an agent waits, so a request is never stranded.
    var visibleTabs: [NotchTab] {
        NotchTab.allCases.filter { !settings.hiddenTabs.contains($0) || ($0 == .dev && !agents.requests.isEmpty) }
    }

    func setTab(_ tab: NotchTab, hidden: Bool) {
        guard tab != .home else { return }
        if hidden {
            settings.hiddenTabs.insert(tab)
            if settings.startTab == tab { settings.startTab = nil }
            if self.tab == tab { self.tab = .home }
        } else {
            settings.hiddenTabs.remove(tab)
        }
    }

    /// Height below the tab bar that the current page needs.
    var pageArea: CGFloat {
        if showSettings { return 320 }
        return switch tab {
        case .home: notes.isOpen ? 190 : homeArea
        case .shelf: 140
        case .reminders: 236
        case .dev: statDetail == nil ? devArea : 330
        }
    }

    /// Cards in the column beside the music; the meeting card only while there's a meeting.
    var homeColumn: [HomeCard] {
        settings.visibleColumnCards.filter { $0 != .meeting || meetings.next != nil }
    }

    /// The music player needs 142; the column only grows past it with all four cards.
    private var homeArea: CGFloat {
        let column = homeColumn.reduce(0) { $0 + $1.height } + CGFloat(max(homeColumn.count - 1, 0)) * 6
        return max(142, column) + Self.pagePadding
    }

    /// The usage row is 160 tall (taller for a question) and the stats/sessions row 82, with 10 between them.
    private var devArea: CGFloat {
        let hidden = settings.hiddenDevCards
        let top: CGFloat = agents.requests.first.map { $0.isQuestion ? Self.questionHeight : 160 }
            ?? (hidden.contains(.usage) ? 0 : 160)
        let bottom = !hidden.contains(.stats) || !hidden.contains(.sessions)
        switch (top > 0, bottom) {
        case (true, true): return top + 10 + 82 + Self.pagePadding
        case (true, false): return top + Self.pagePadding
        default: return 102
        }
    }

    /// The most urgent thing to show beside the closed notch, if any.
    var activity: NotchActivity? {
        if focusTimer.celebrating { return .celebration }
        let alert = agents.alert
        if let alert, alert.pending { return .agent(alert) }
        if let warning = usage.warning { return .usage(warning) }
        // Questions and approvals always show; the "Done" flash can be turned off in Settings.
        if let alert, settings.showFinishedAlert { return .agent(alert) }
        if let meeting = meetings.imminent, !settings.hiddenHomeCards.contains(.meeting) { return .meeting(meeting) }
        if settings.showMusicWing, nowPlaying.isPlaying, nowPlaying.hasContent { return .music }
        return nil
    }

    var panelSize: CGSize {
        let area = showClipboard ? max(pageArea, Self.clipboardArea) : pageArea
        return CGSize(width: settings.panelWidth, height: notchSize.height + area)
    }

    /// The largest the panel can get; the window is sized to fit it plus shadow.
    var maxPanelSize: CGSize { CGSize(width: AppSettings.panelWidths.max() ?? 680, height: notchSize.height + 340) }

    /// Esc steps back one level before closing the notch. Returns false when nothing was open.
    func dismissOverlay() -> Bool {
        if showClipboard { showClipboard = false; return true }
        if showSettings { showSettings = false; return true }
        if notes.isOpen { notes.close(); return true }
        if statDetail != nil { statDetail = nil; return true }
        return false
    }

    func resetOverlays() {
        showClipboard = false
        showSettings = false
        showWelcome = false
        statDetail = nil
        notes.close()
    }
}
