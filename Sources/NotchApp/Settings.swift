import Foundation
import Observation
import SwiftUI

/// Where agent questions and approvals are answered.
enum PromptRouting: String {
    case notch, auto, terminal
}

enum HomeCard: String, CaseIterable {
    case music, timer, vpn, note, meeting

    var title: String {
        switch self {
        case .music: "Music player"
        case .timer: "Focus timer"
        case .vpn: "VPN"
        case .note: "Quick note"
        case .meeting: "Next meeting"
        }
    }
}

/// A countdown added in Settings, like a debate speech.
struct CustomPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var minutes: Int
    /// Keeps what's left when another preset is picked, like a debate prep-time bank.
    var bank = false
}

enum DevCard: String, CaseIterable {
    case usage, stats, sessions

    var title: String {
        switch self {
        case .usage: "Usage limits"
        case .stats: "System stats"
        case .sessions: "Agent sessions"
        }
    }
}

enum AccentChoice: String, CaseIterable {
    case standard, blue, purple, pink, orange, green, graphite

    /// nil keeps the built-in colors: green switches, blue highlights.
    var color: Color? {
        switch self {
        case .standard: nil
        case .blue: Color(red: 0.27, green: 0.58, blue: 1)
        case .purple: Color(red: 0.69, green: 0.42, blue: 1)
        case .pink: Color(red: 1, green: 0.36, blue: 0.62)
        case .orange: Color(red: 1, green: 0.6, blue: 0.2)
        case .green: Color(red: 0.3, green: 0.82, blue: 0.42)
        case .graphite: Color(white: 0.62)
        }
    }
}

/// Preferences from the Settings page, saved to UserDefaults as they change.
@Observable
@MainActor
final class AppSettings {
    /// Seconds the pointer rests on the notch before it opens.
    var openDelay: Double { didSet { defaults.set(openDelay, forKey: "openDelay") } }
    /// Seconds after the pointer leaves before the panel closes.
    var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: "closeDelay") } }
    /// Open only when the closed notch is clicked, instead of on hover.
    var openOnClick: Bool { didSet { defaults.set(openOnClick, forKey: "openOnClick") } }
    /// The page the notch opens to; nil reopens the last page used.
    var startTab: NotchTab? { didSet { defaults.set(startTab?.rawValue, forKey: "startTab") } }
    /// Home can't be hidden: it's where the notch falls back to.
    var hiddenTabs: Set<NotchTab> { didSet { defaults.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs") } }
    var showMirrorButton: Bool { didSet { defaults.set(showMirrorButton, forKey: "showMirrorButton") } }
    var mediaSource: MediaSource { didSet { defaults.set(mediaSource.rawValue, forKey: "mediaSource") } }
    /// Top-to-bottom order of the small cards beside the music player.
    var homeOrder: [HomeCard] { didSet { defaults.set(homeOrder.map(\.rawValue), forKey: "homeOrder") } }
    var hiddenHomeCards: Set<HomeCard> { didSet { defaults.set(hiddenHomeCards.map(\.rawValue), forKey: "hiddenHomeCards") } }
    var hiddenDevCards: Set<DevCard> { didSet { defaults.set(hiddenDevCards.map(\.rawValue), forKey: "hiddenDevCards") } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: "panelWidth") } }
    var promptRouting: PromptRouting { didSet { defaults.set(promptRouting.rawValue, forKey: "promptRouting") } }
    /// The green "Done" beside the closed notch when an agent finishes a turn.
    var showFinishedAlert: Bool { didSet { defaults.set(showFinishedAlert, forKey: "showFinishedAlert") } }
    /// Flash beside the closed notch when a Claude or Codex limit passes 80% and 95%.
    var usageWarnings: Bool { didSet { defaults.set(usageWarnings, forKey: "usageWarnings") } }
    /// Artwork and bars beside the closed notch while music plays.
    var showMusicWing: Bool { didSet { defaults.set(showMusicWing, forKey: "showMusicWing") } }
    /// Preset name to length in minutes, for presets the user changed.
    var timerMinutes: [String: Int] { didSet { defaults.set(timerMinutes, forKey: "timerMinutes") } }
    /// A system sound name; empty plays nothing.
    var timerSound: String { didSet { defaults.set(timerSound, forKey: "timerSound") } }
    var timerCelebration: Bool { didSet { defaults.set(timerCelebration, forKey: "timerCelebration") } }
    var customPresets: [CustomPreset] { didSet { defaults.set(try? JSONEncoder().encode(customPresets), forKey: "customPresets") } }
    /// Shortcut names run when a countdown (not a break) starts and when it ends; empty runs nothing.
    var focusStartShortcut: String { didSet { defaults.set(focusStartShortcut, forKey: "focusStartShortcut") } }
    var focusEndShortcut: String { didSet { defaults.set(focusEndShortcut, forKey: "focusEndShortcut") } }
    var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    var clipboardPaused: Bool { didSet { defaults.set(clipboardPaused, forKey: "clipboardPaused") } }
    /// Set once the Connections page has been shown on first open.
    var didShowSetup: Bool { didSet { defaults.set(didShowSetup, forKey: "didShowSetup") } }

    static let panelWidths: [Double] = [680, 760, 840]
    static let columnCards: [HomeCard] = [.timer, .vpn, .note, .meeting]

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        openDelay = defaults.object(forKey: "openDelay") as? Double ?? 0.1
        closeDelay = defaults.object(forKey: "closeDelay") as? Double ?? 0.15
        openOnClick = defaults.bool(forKey: "openOnClick")
        startTab = defaults.string(forKey: "startTab").flatMap(NotchTab.init(rawValue:))
        hiddenTabs = Set((defaults.stringArray(forKey: "hiddenTabs") ?? []).compactMap(NotchTab.init(rawValue:)))
        showMirrorButton = defaults.object(forKey: "showMirrorButton") as? Bool ?? true
        mediaSource = defaults.string(forKey: "mediaSource").flatMap(MediaSource.init(rawValue:)) ?? .automatic
        // Keep only known column cards, and add any a newer version introduced.
        let savedOrder = (defaults.stringArray(forKey: "homeOrder") ?? []).compactMap(HomeCard.init(rawValue:))
            .filter(Self.columnCards.contains)
        homeOrder = savedOrder + Self.columnCards.filter { !savedOrder.contains($0) }
        hiddenHomeCards = Set((defaults.stringArray(forKey: "hiddenHomeCards") ?? []).compactMap(HomeCard.init(rawValue:)))
        hiddenDevCards = Set((defaults.stringArray(forKey: "hiddenDevCards") ?? []).compactMap(DevCard.init(rawValue:)))
        accent = defaults.string(forKey: "accent").flatMap(AccentChoice.init(rawValue:)) ?? .standard
        let width = defaults.object(forKey: "panelWidth") as? Double ?? 680
        panelWidth = Self.panelWidths.contains(width) ? width : 680
        promptRouting = defaults.string(forKey: "promptRouting").flatMap(PromptRouting.init(rawValue:)) ?? .auto
        showFinishedAlert = defaults.object(forKey: "showFinishedAlert") as? Bool ?? true
        usageWarnings = defaults.object(forKey: "usageWarnings") as? Bool ?? true
        showMusicWing = defaults.object(forKey: "showMusicWing") as? Bool ?? true
        timerMinutes = defaults.dictionary(forKey: "timerMinutes") as? [String: Int] ?? [:]
        timerSound = defaults.string(forKey: "timerSound") ?? "Hero"
        timerCelebration = defaults.object(forKey: "timerCelebration") as? Bool ?? true
        customPresets = defaults.data(forKey: "customPresets").flatMap { try? JSONDecoder().decode([CustomPreset].self, from: $0) } ?? []
        focusStartShortcut = defaults.string(forKey: "focusStartShortcut") ?? ""
        focusEndShortcut = defaults.string(forKey: "focusEndShortcut") ?? ""
        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 50
        clipboardPaused = defaults.bool(forKey: "clipboardPaused")
        didShowSetup = defaults.bool(forKey: "didShowSetup")
    }

    /// Cards shown in the column beside the music player, in order.
    var visibleColumnCards: [HomeCard] { homeOrder.filter { !hiddenHomeCards.contains($0) } }

    func moveColumnCard(_ card: HomeCard, by offset: Int) {
        guard let index = homeOrder.firstIndex(of: card), homeOrder.indices.contains(index + offset) else { return }
        homeOrder.swapAt(index, index + offset)
    }
}
