import Foundation
import Observation

/// Preferences from the Settings page, saved to UserDefaults as they change.
@Observable
@MainActor
final class AppSettings {
    /// Seconds the pointer rests on the notch before it opens.
    var openDelay: Double { didSet { defaults.set(openDelay, forKey: "openDelay") } }
    /// Seconds after the pointer leaves before the panel closes.
    var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: "closeDelay") } }
    /// The page the notch opens to; nil reopens the last page used.
    var startTab: NotchTab? { didSet { defaults.set(startTab?.rawValue, forKey: "startTab") } }
    /// Home can't be hidden: it's where the notch falls back to.
    var hiddenTabs: Set<NotchTab> { didSet { defaults.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs") } }
    var showMirrorButton: Bool { didSet { defaults.set(showMirrorButton, forKey: "showMirrorButton") } }
    /// The green "Done" beside the closed notch when an agent finishes a turn.
    var showFinishedAlert: Bool { didSet { defaults.set(showFinishedAlert, forKey: "showFinishedAlert") } }
    /// Preset name to length in minutes, for presets the user changed.
    var timerMinutes: [String: Int] { didSet { defaults.set(timerMinutes, forKey: "timerMinutes") } }
    /// A system sound name; empty plays nothing.
    var timerSound: String { didSet { defaults.set(timerSound, forKey: "timerSound") } }
    var timerCelebration: Bool { didSet { defaults.set(timerCelebration, forKey: "timerCelebration") } }
    var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    var clipboardPaused: Bool { didSet { defaults.set(clipboardPaused, forKey: "clipboardPaused") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        openDelay = defaults.object(forKey: "openDelay") as? Double ?? 0.1
        closeDelay = defaults.object(forKey: "closeDelay") as? Double ?? 0.15
        startTab = defaults.string(forKey: "startTab").flatMap(NotchTab.init(rawValue:))
        hiddenTabs = Set((defaults.stringArray(forKey: "hiddenTabs") ?? []).compactMap(NotchTab.init(rawValue:)))
        showMirrorButton = defaults.object(forKey: "showMirrorButton") as? Bool ?? true
        showFinishedAlert = defaults.object(forKey: "showFinishedAlert") as? Bool ?? true
        timerMinutes = defaults.dictionary(forKey: "timerMinutes") as? [String: Int] ?? [:]
        timerSound = defaults.string(forKey: "timerSound") ?? "Hero"
        timerCelebration = defaults.object(forKey: "timerCelebration") as? Bool ?? true
        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 50
        clipboardPaused = defaults.bool(forKey: "clipboardPaused")
    }
}
