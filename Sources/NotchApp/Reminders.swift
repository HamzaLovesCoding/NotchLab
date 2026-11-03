import EventKit
import Observation
import SwiftUI

struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

struct ReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let dueHasTime: Bool
    let listID: String
    let flagged: Bool
    let created: Date?

    init(_ reminder: EKReminder) {
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? ""
        let components = reminder.dueDateComponents
        due = components.flatMap { Calendar.current.date(from: $0) }
        dueHasTime = components?.hour != nil
        listID = reminder.calendar?.calendarIdentifier ?? ""
        flagged = reminder.priority == Int(EKReminderPriority.high.rawValue)
        created = reminder.creationDate
    }
}

/// Apple Reminders through EventKit. Edits are written straight to the Reminders database,
/// so they sync through iCloud like changes made in the Reminders app.
@Observable
@MainActor
final class RemindersStore {
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access
    private(set) var lists: [ReminderList] = []
    private(set) var reminders: [ReminderItem] = []
    /// Reminders just ticked off; they stay visible briefly so the check registers.
    private(set) var completing: Set<String> = []
    private(set) var error: String?
    /// nil shows every list.
    var selectedListID: String? {
        didSet { UserDefaults.standard.set(selectedListID, forKey: "remindersList") }
    }

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var fetchGeneration = 0

    init() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
        selectedListID = UserDefaults.standard.string(forKey: "remindersList")
    }

    var visibleReminders: [ReminderItem] {
        guard let selectedListID else { return reminders }
        return reminders.filter { $0.listID == selectedListID }
    }

    var selectedList: ReminderList? { lists.first { $0.id == selectedListID } }

    func count(in listID: String?) -> Int {
        guard let listID else { return reminders.count }
        return reminders.reduce(0) { $0 + ($1.listID == listID ? 1 : 0) }
    }

    func list(for item: ReminderItem) -> ReminderList? { lists.first { $0.id == item.listID } }

    /// Returns the request so Connect all can wait for the answer before the next prompt.
    @discardableResult
    func requestAccess() -> Task<Void, Never> {
        Task {
            do {
                let granted = try await store.requestFullAccessToReminders()
                access = granted ? .granted : .denied
                if granted { reload() }
            } catch {
                access = .denied
            }
        }
    }

    func reload() {
        guard access == .granted else { return }
        startObserving()
        lists = store.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if let selectedListID, !lists.contains(where: { $0.id == selectedListID }) { self.selectedListID = nil }

        fetchGeneration += 1
        let generation = fetchGeneration
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] result in
            // EKReminder isn't Sendable; convert to value types on EventKit's queue.
            let items = (result ?? []).map(ReminderItem.init)
            DispatchQueue.main.async {
                guard let self, generation == self.fetchGeneration else { return }
                self.reminders = items.sorted(by: Self.order)
            }
        }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            completing.insert(item.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self.reminders.removeAll { $0.id == item.id }
                    self.completing.remove(item.id)
                }
            }
        } catch {
            self.error = "Couldn't complete: \(error.localizedDescription)"
        }
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = selectedListID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else {
            error = "No Reminders list to add to"
            return
        }
        do {
            try store.save(reminder, commit: true)
            error = nil
            reload()
        } catch {
            self.error = "Couldn't add: \(error.localizedDescription)"
        }
    }

    func delete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        do {
            try store.remove(reminder, commit: true)
            reminders.removeAll { $0.id == item.id }
        } catch {
            self.error = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    private func startObserving() {
        guard observer == nil else { return }
        // Fires for changes made anywhere: the Reminders app, iPhone via iCloud, or here.
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Dated reminders first (soonest first), then undated ones oldest first.
    private nonisolated static func order(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        switch (a.due, b.due) {
        case let (dueA?, dueB?): return dueA < dueB
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return (a.created ?? .distantPast) < (b.created ?? .distantPast)
        }
    }
}
