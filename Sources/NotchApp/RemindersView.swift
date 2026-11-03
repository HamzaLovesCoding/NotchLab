import SwiftUI

struct RemindersView: View {
    let store: RemindersStore
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            switch store.access {
            case .granted: content
            case .notDetermined: accessPrompt
            case .denied: deniedMessage
            }
        }
        .onAppear { store.reload() }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                ListButton(title: "All", color: .white, count: store.count(in: nil), selected: store.selectedListID == nil) {
                    store.selectedListID = nil
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.lists) { list in
                            ListButton(title: list.title, color: list.color, count: store.count(in: list.id),
                                       selected: store.selectedListID == list.id) {
                                store.selectedListID = list.id
                            }
                        }
                    }
                }
            }
            .frame(width: 150)

            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.selectedList?.title ?? "All Reminders")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(store.selectedList?.color ?? .white)
                        Spacer()
                        if let error = store.error {
                            Text(error).font(.system(size: 10)).foregroundStyle(.red.opacity(0.8)).lineLimit(1)
                        } else {
                            Text("\(store.visibleReminders.count) left")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    if store.visibleReminders.isEmpty {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("All done", systemImage: "checkmark.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(store.visibleReminders) { item in
                                    ReminderRow(item: item, store: store)
                                }
                            }
                        }
                    }
                    NewReminderField(store: store)
                }
            }
        }
    }

    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text("See and check off your Apple Reminders here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Button { store.requestAccess() } label: {
                Text("Connect Reminders")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent ?? .notchBlue))
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedMessage: some View {
        VStack(spacing: 10) {
            Text("Reminders access is off")
                .font(.system(size: 13, weight: .semibold))
            Text("Turn on NotchApp in System Settings › Privacy & Security › Reminders, then reopen the app.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent ?? .notchBlue)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ListButton: View {
    let title: String
    let color: Color
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(selected ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let store: RemindersStore

    var body: some View {
        let done = store.completing.contains(item.id)
        let color = store.list(for: item)?.color ?? .white
        HStack(alignment: .top, spacing: 10) {
            Button { if !done { store.complete(item) } } label: {
                ZStack {
                    Circle().strokeBorder(color.opacity(done ? 1 : 0.6), lineWidth: 1.5)
                    if done { Circle().fill(color).padding(3.5) }
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(done ? 0.4 : 0.92))
                    .strikethrough(done)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(subtitle.overdue ? Color.red.opacity(0.85) : .white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
            if item.flagged {
                Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Complete") { store.complete(item) }
            Button("Delete") { store.delete(item) }
            Divider()
            Button("Open Reminders") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    private var subtitle: (text: String, overdue: Bool)? {
        var parts: [String] = []
        var overdue = false
        if let due = item.due {
            let calendar = Calendar.current
            overdue = item.dueHasTime ? due < Date() : due < calendar.startOfDay(for: Date())
            let day: String
            if calendar.isDateInToday(due) { day = "Today" }
            else if calendar.isDateInTomorrow(due) { day = "Tomorrow" }
            else if calendar.isDateInYesterday(due) { day = "Yesterday" }
            else { day = due.formatted(.dateTime.month(.abbreviated).day()) }
            parts.append(item.dueHasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day)
        }
        if store.selectedListID == nil, let list = store.list(for: item) { parts.append(list.title) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), overdue)
    }
}

private struct NewReminderField: View {
    let store: RemindersStore
    @State private var text = ""
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(store.selectedList?.color ?? accent ?? .notchBlue)
            TextField("New reminder", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    store.add(title: text)
                    text = ""
                }
        }
        .padding(.top, 4)
    }
}
