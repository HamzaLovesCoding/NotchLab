import AppKit
import Observation

enum NotchTab: CaseIterable {
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

/// UI state shared between the AppKit window controller and the SwiftUI views.
@Observable
@MainActor
final class NotchModel {
    var isExpanded = false
    var tab: NotchTab = .home
    var statDetail: StatKind?
    var showClipboard = false
    var notchSize = CGSize(width: 200, height: 32)

    /// Highlighted drop zone while a file drag hovers the panel.
    var dropTarget: DropTarget?
    /// AirDrop tile frame in the hosting view's (top-left origin) space, used to route drops.
    var airDropFrame: CGRect = .zero

    let nowPlaying = NowPlaying()
    let audioOutputs = AudioOutputs()
    let focusTimer = FocusTimer()
    let mirror = Mirror()
    let notes = NotesStore()
    let vpn = VPNController()
    let clipboard = ClipboardHistory()
    let shelf = Shelf()
    let reminders = RemindersStore()
    let usage = UsageStore()
    let system = SystemMonitor()
    let agents = AgentMonitor()

    init() {
        // The next hover should land on the request, so switch pages while the notch is closed.
        agents.onRequest = { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.resetOverlays()
            self.tab = .dev
        }
    }

    static let panelWidth: CGFloat = 680
    /// Vertical padding around page content (6 above, 14 below).
    static let pagePadding: CGFloat = 20
    private static let clipboardArea: CGFloat = 330

    /// Height below the tab bar that the current page needs.
    var pageArea: CGFloat {
        switch tab {
        case .home: notes.isOpen ? 190 : 162
        case .shelf: 140
        case .reminders: 236
        case .dev: statDetail == nil ? 272 : 330
        }
    }

    var panelSize: CGSize {
        let area = showClipboard ? max(pageArea, Self.clipboardArea) : pageArea
        return CGSize(width: Self.panelWidth, height: notchSize.height + area)
    }

    /// The largest the panel can get; the window is sized to fit it plus shadow.
    var maxPanelSize: CGSize { CGSize(width: Self.panelWidth, height: notchSize.height + 340) }

    /// Esc steps back one level before closing the notch. Returns false when nothing was open.
    func dismissOverlay() -> Bool {
        if showClipboard { showClipboard = false; return true }
        if notes.isOpen { notes.close(); return true }
        if statDetail != nil { statDetail = nil; return true }
        return false
    }

    func resetOverlays() {
        showClipboard = false
        statDetail = nil
        notes.close()
    }
}
