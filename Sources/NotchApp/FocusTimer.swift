import AppKit
import Observation
import SwiftUI

struct TimerPreset: Identifiable, Equatable {
    /// The name for built-in presets, a UUID for ones added in Settings.
    let id: String
    let name: String
    /// Length until the user picks another in Settings.
    let minutes: Int
    let color: Color
    var bank = false
    var isCustom = false
    var isBreak: Bool { id == "Break" }
    /// For presets added in Settings.
    static let addedColor = Color(red: 0.3, green: 0.8, blue: 0.82)

    init(name: String, minutes: Int, color: Color) {
        id = name
        self.name = name
        self.minutes = minutes
        self.color = color
    }

    init(custom: CustomPreset) {
        id = custom.id.uuidString
        name = custom.name.isEmpty ? "Preset" : custom.name
        minutes = custom.minutes
        color = Self.addedColor
        bank = custom.bank
        isCustom = true
    }
}

/// Countdown timer. Stores an end date rather than ticking, so nothing runs while the
/// notch is closed except a single one-shot timer for the completion chime. The end date
/// is saved, so a countdown carries on after NotchLab restarts.
@Observable
@MainActor
final class FocusTimer {
    static let presets = [
        TimerPreset(name: "Focus", minutes: 25, color: Color(red: 0.96, green: 0.6, blue: 0.27)),
        TimerPreset(name: "Break", minutes: 5, color: Color(red: 0.4, green: 0.8, blue: 0.42)),
        TimerPreset(name: "Deep", minutes: 50, color: Color(red: 0.78, green: 0.33, blue: 0.93)),
    ]
    static let customColor = Color(red: 0.27, green: 0.58, blue: 1)

    private(set) var duration: TimeInterval
    /// nil when the time was typed in by hand.
    private(set) var presetID: String?
    private(set) var endDate: Date? { didSet { UserDefaults.standard.set(endDate, forKey: "timerEnd") } }
    private(set) var pausedRemaining: TimeInterval? { didSet { UserDefaults.standard.set(pausedRemaining, forKey: "timerPaused") } }
    /// True for a few seconds after a countdown ends; drives the notch celebration.
    private(set) var celebrating = false
    private(set) var lastFinishedWasBreak = false
    private(set) var finishedColor = Color.green
    private var sessionDay: Date
    private var sessionCount: Int
    /// Time left in each bank preset that was switched away from mid-countdown.
    @ObservationIgnored private var banks: [String: TimeInterval] = [:] {
        didSet { UserDefaults.standard.set(banks, forKey: "timerBanks") }
    }
    @ObservationIgnored private var completion: Timer?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        let defaults = UserDefaults.standard
        let saved = defaults.double(forKey: "timerDuration")
        duration = saved > 0 ? saved : 25 * 60
        let known = Self.presets.map(\.id) + settings.customPresets.map(\.id.uuidString)
        presetID = defaults.string(forKey: "timerPreset").flatMap { known.contains($0) ? $0 : nil }
            ?? (saved > 0 ? nil : Self.presets[0].id)
        sessionDay = defaults.object(forKey: "timerSessionDay") as? Date ?? .distantPast
        sessionCount = defaults.integer(forKey: "timerSessionCount")
        banks = defaults.dictionary(forKey: "timerBanks") as? [String: TimeInterval] ?? [:]
        pausedRemaining = defaults.object(forKey: "timerPaused") as? TimeInterval
        if let end = defaults.object(forKey: "timerEnd") as? Date {
            if end > Date() {
                endDate = end
                scheduleCompletion(after: end.timeIntervalSinceNow)
            } else {
                // It ran out while NotchLab was closed: count it, but don't chime late.
                finish(quietly: true)
            }
        }
    }

    var allPresets: [TimerPreset] { Self.presets + settings.customPresets.map(TimerPreset.init(custom:)) }
    var preset: TimerPreset? { allPresets.first { $0.id == presetID } }
    var isRunning: Bool { endDate != nil }
    var isIdle: Bool { endDate == nil && pausedRemaining == nil }
    var color: Color { preset?.color ?? Self.customColor }
    /// Finished non-break countdowns today.
    var sessionsToday: Int { Calendar.current.isDateInToday(sessionDay) ? sessionCount : 0 }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        if isIdle, preset?.isBreak != true { runShortcut(settings.focusStartShortcut) }
        let remaining = pausedRemaining ?? duration
        endDate = Date().addingTimeInterval(remaining)
        pausedRemaining = nil
        scheduleCompletion(after: remaining)
    }

    func pause() {
        pausedRemaining = remaining(at: Date())
        endDate = nil
        completion?.invalidate()
    }

    /// Back to the full length; a bank preset starts over full too.
    func reset() {
        if let presetID { banks[presetID] = nil }
        clear()
    }

    func select(_ preset: TimerPreset) {
        // A bank (like debate prep time) keeps what's left for the next time it's picked.
        if let current = self.preset, current.bank, !isIdle { banks[current.id] = remaining(at: Date()) }
        presetID = preset.id
        setDuration(TimeInterval(minutes(for: preset) * 60), keepPreset: true)
        if preset.bank, let left = banks[preset.id] { pausedRemaining = left }
    }

    func minutes(for preset: TimerPreset) -> Int {
        if preset.isCustom { return settings.customPresets.first { $0.id.uuidString == preset.id }?.minutes ?? preset.minutes }
        return settings.timerMinutes[preset.name] ?? preset.minutes
    }

    /// Saves a new preset length, and applies it now if that preset is selected and not counting down.
    func setMinutes(_ minutes: Int, for preset: TimerPreset) {
        if preset.isCustom {
            guard let index = settings.customPresets.firstIndex(where: { $0.id.uuidString == preset.id }) else { return }
            settings.customPresets[index].minutes = minutes
        } else {
            settings.timerMinutes[preset.name] = minutes
        }
        if presetID == preset.id, isIdle { select(preset) }
    }

    func remove(_ custom: CustomPreset) {
        let removedID = custom.id.uuidString
        banks[removedID] = nil
        settings.customPresets.removeAll { $0.id == custom.id }
        if presetID == removedID { select(Self.presets[0]) }
    }

    /// A typed-in time. Ignored if it adds up to zero.
    func setDuration(_ seconds: TimeInterval, keepPreset: Bool = false) {
        guard seconds > 0 else { return }
        if !keepPreset { presetID = nil }
        duration = seconds
        clear()
        UserDefaults.standard.set(duration, forKey: "timerDuration")
        UserDefaults.standard.set(presetID, forKey: "timerPreset")
    }

    /// Stops the countdown without touching banks.
    private func clear() {
        if !isIdle, preset?.isBreak != true { runShortcut(settings.focusEndShortcut) }
        endDate = nil
        pausedRemaining = nil
        completion?.invalidate()
    }

    private func scheduleCompletion(after seconds: TimeInterval) {
        completion?.invalidate()
        completion = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    private func finish(quietly: Bool = false) {
        let finished = preset
        endDate = nil
        pausedRemaining = nil
        if let presetID { banks[presetID] = nil }
        lastFinishedWasBreak = finished?.isBreak == true
        finishedColor = color
        // A used-up prep bank isn't a focus session.
        if !lastFinishedWasBreak, finished?.bank != true {
            sessionCount = sessionsToday + 1
            sessionDay = Date()
            UserDefaults.standard.set(sessionCount, forKey: "timerSessionCount")
            UserDefaults.standard.set(sessionDay, forKey: "timerSessionDay")
        }
        if !lastFinishedWasBreak { runShortcut(settings.focusEndShortcut) }
        // Pomodoro rhythm: Focus queues up a Break and a Break queues Focus. Other times repeat.
        if finished?.id == "Focus" { select(Self.presets[1]) } else if lastFinishedWasBreak { select(Self.presets[0]) }
        guard !quietly else { return }
        if !settings.timerSound.isEmpty { NSSound(named: settings.timerSound)?.play() }
        guard settings.timerCelebration else { return }
        celebrating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.celebrating = false }
    }

    // MARK: Shortcuts

    /// Runs one of the user's Shortcuts (say, one that turns a Focus mode on) without waiting for it.
    private func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// The user's shortcuts, for the pickers in Settings. Takes a moment, so call it off the main thread.
    nonisolated static func shortcutNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output.split(separator: "\n").map(String.init).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
