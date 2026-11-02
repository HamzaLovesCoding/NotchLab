import AppKit
import Observation
import SwiftUI

struct TimerPreset: Identifiable, Equatable {
    let name: String
    let minutes: Int
    let color: Color
    var id: String { name }
    var isBreak: Bool { name == "Break" }
}

/// Countdown timer. Stores an end date rather than ticking, so nothing runs while the
/// notch is closed except a single one-shot timer for the completion chime.
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
    private(set) var preset: TimerPreset?
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    /// True for a few seconds after a countdown ends; drives the notch celebration.
    private(set) var celebrating = false
    private(set) var lastFinishedWasBreak = false
    private(set) var finishedColor = Color.green
    private var sessionDay: Date
    private var sessionCount: Int
    @ObservationIgnored private var completion: Timer?

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.double(forKey: "timerDuration")
        duration = saved > 0 ? saved : 25 * 60
        preset = Self.presets.first { $0.name == defaults.string(forKey: "timerPreset") }
            ?? (saved > 0 ? nil : Self.presets[0])
        sessionDay = defaults.object(forKey: "timerSessionDay") as? Date ?? .distantPast
        sessionCount = defaults.integer(forKey: "timerSessionCount")
    }

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
        let remaining = pausedRemaining ?? duration
        endDate = Date().addingTimeInterval(remaining)
        pausedRemaining = nil
        completion?.invalidate()
        completion = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    func pause() {
        pausedRemaining = remaining(at: Date())
        endDate = nil
        completion?.invalidate()
    }

    func reset() {
        endDate = nil
        pausedRemaining = nil
        completion?.invalidate()
    }

    func select(_ preset: TimerPreset) {
        self.preset = preset
        setDuration(TimeInterval(preset.minutes * 60), keepPreset: true)
    }

    /// A typed-in time. Ignored if it adds up to zero.
    func setDuration(_ seconds: TimeInterval, keepPreset: Bool = false) {
        guard seconds > 0 else { return }
        if !keepPreset { preset = nil }
        duration = seconds
        reset()
        UserDefaults.standard.set(duration, forKey: "timerDuration")
        UserDefaults.standard.set(preset?.name, forKey: "timerPreset")
    }

    private func finish() {
        endDate = nil
        pausedRemaining = nil
        lastFinishedWasBreak = preset?.isBreak == true
        finishedColor = color
        if !lastFinishedWasBreak {
            sessionCount = sessionsToday + 1
            sessionDay = Date()
            UserDefaults.standard.set(sessionCount, forKey: "timerSessionCount")
            UserDefaults.standard.set(sessionDay, forKey: "timerSessionDay")
        }
        // Pomodoro rhythm: Focus queues up a Break and a Break queues Focus. Other times repeat.
        if preset?.name == "Focus" { select(Self.presets[1]) } else if lastFinishedWasBreak { select(Self.presets[0]) }
        NSSound(named: "Hero")?.play()
        celebrating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.celebrating = false }
    }
}
