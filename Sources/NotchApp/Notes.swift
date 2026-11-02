import Observation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var body = ""
    var updated = Date()

    static let accent = Color(red: 1, green: 0.84, blue: 0.27)

    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The first line doubles as the title, so there's no separate title field.
    var title: String { lines.first ?? "New note" }
    var preview: String { lines.dropFirst().first ?? "" }

    private var lines: [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

@Observable
@MainActor
final class NotesStore {
    private(set) var notes: [Note] = []
    /// While true the notes editor replaces the home page.
    private(set) var isOpen = false
    private(set) var selectedID: UUID?

    private static let defaultsKey = "notes"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        } else if let legacy = UserDefaults.standard.string(forKey: "quickNote"), !legacy.isEmpty {
            // Carry over the single quick note from the first version.
            notes = [Note(body: legacy)]
            save()
            UserDefaults.standard.removeObject(forKey: "quickNote")
        }
    }

    var sortedNotes: [Note] { notes.sorted { $0.updated > $1.updated } }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    func open() {
        selectedID = sortedNotes.first?.id
        if selectedID == nil { newNote() }
        isOpen = true
    }

    func newNote() {
        if let selectedID, note(selectedID)?.isEmpty == true { return }
        let note = Note()
        notes.append(note)
        select(note.id)
    }

    /// Quick capture from the home page: saves without opening the editor.
    func add(_ text: String) {
        notes.append(Note(body: text))
        save()
    }

    func select(_ id: UUID) {
        selectedID = id
        dropEmptyNotes()
    }

    func update(_ id: UUID, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].updated = Date()
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
        if selectedID == id {
            selectedID = sortedNotes.first?.id
            if selectedID == nil { newNote() }
        }
    }

    func close() {
        selectedID = nil
        dropEmptyNotes()
        isOpen = false
    }

    /// Keeps the note being edited even if it's still blank.
    private func dropEmptyNotes() {
        let before = notes.count
        notes.removeAll { $0.isEmpty && $0.id != selectedID }
        if notes.count != before { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
