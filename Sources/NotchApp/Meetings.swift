import AppKit
import EventKit
import Observation
import SwiftUI

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    /// The video-call link, when the event has one.
    let joinURL: URL?

    /// "in 5m", "in 1h 20m", or "Now" once it has started.
    func countdown(at date: Date) -> String {
        let minutes = Int((start.timeIntervalSince(date) / 60).rounded(.up))
        if minutes <= 0 { return "Now" }
        return minutes < 60 ? "in \(minutes)m" : "in \(minutes / 60)h \(minutes % 60)m"
    }
}

/// The next calendar event, for the Home card and the closed notch. EventKit covers every
/// account in the Calendar app (iCloud, Google, Exchange, ...).
@Observable
@MainActor
final class MeetingsStore {
    /// The next meeting, or one that started in the last 5 minutes.
    private(set) var next: Meeting?
    /// The same meeting, from 10 minutes before it starts; shown beside the closed notch.
    private(set) var imminent: Meeting?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let callHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                    "webex.com", "facetime.apple.com", "whereby.com"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func start() {
        guard timer == nil else { return }
        reload()
        // Moves on to the next meeting and keeps the closed notch current; reading 12 hours
        // of events is quick enough to just do it again.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Returns the request so Connect all can wait for the answer before the next prompt.
    @discardableResult
    func requestAccess() -> Task<Void, Never> {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            reload()
        }
    }

    func reload() {
        let now = Date()
        var found: Meeting?
        if hasAccess {
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: now.addingTimeInterval(12 * 3600),
                                                     calendars: nil)
            found = store.events(matching: predicate)
                .filter { !$0.isAllDay && $0.status != .canceled && !Self.declined($0) && $0.startDate > now.addingTimeInterval(-300) }
                .min { $0.startDate < $1.startDate }
                .map(Self.meeting)
        }
        let soon = found.flatMap { $0.start.timeIntervalSince(now) <= 600 ? $0 : nil }
        if next != found { next = found }
        if imminent != soon { imminent = soon }
    }

    func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func meeting(_ event: EKEvent) -> Meeting {
        let title = event.title ?? ""
        // Repeating events share an identifier, so the start time tells occurrences apart.
        return Meeting(id: (event.eventIdentifier ?? "") + "\(event.startDate.timeIntervalSince1970)",
                       title: title.isEmpty ? "Untitled event" : title,
                       start: event.startDate, end: event.endDate,
                       color: Color(cgColor: event.calendar.cgColor), joinURL: joinLink(event))
    }

    /// A Zoom, Meet, Teams, ... link from the event's URL, location, or notes.
    private static func joinLink(_ event: EKEvent) -> URL? {
        func isCall(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return callHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, isCall(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let linkDetector else { return nil }
        return linkDetector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: isCall)
    }
}
