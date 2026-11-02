import SwiftUI

/// Replaces the home page while notes are open: the list on the left, the selected note on the right.
struct NotesPanel: View {
    let store: NotesStore
    @FocusState private var editorFocused: Bool
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Notes").font(.system(size: 14, weight: .bold))
                Spacer()
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy note", action: copyNote)
                IconButton(symbol: "plus", help: "New note") {
                    store.newNote()
                    focusEditor()
                }
                Button("Done", action: store.close)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Note.accent)
                    .padding(.leading, 6)
            }
            .frame(height: 22)

            HStack(spacing: 10) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(store.sortedNotes) { note in
                            NoteListRow(note: note, selected: note.id == store.selectedID,
                                        select: { store.select(note.id) }, delete: { store.delete(note.id) })
                        }
                    }
                }
                .frame(width: 160)
                if let id = store.selectedID { editor(id) }
            }
        }
    }

    private func editor(_ id: UUID) -> some View {
        let text = Binding(get: { store.note(id)?.body ?? "" }, set: { store.update(id, body: $0) })
        return ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($editorFocused)
                .padding(.horizontal, 5)
                .padding(.vertical, 7)
            if text.wrappedValue.isEmpty {
                Text("Start typing…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.leading, 10)
                    .padding(.top, 7)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func copyNote() {
        guard let id = store.selectedID, let note = store.note(id), !note.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.body, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    /// The panel only becomes key when a text view is clicked, so a button press has to make
    /// it key before the editor can take typing.
    private func focusEditor() {
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
        editorFocused = true
    }
}

private struct NoteListRow: View {
    let note: Note
    let selected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                Text(note.preview.isEmpty ? relativeTime(note.updated) : "\(relativeTime(note.updated))  \(note.preview)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.trailing, hovering ? 24 : 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(selected ? 0.1 : (hovering ? 0.05 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovering {
                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Delete note")
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("Delete", action: delete) }
    }
}

/// Home page entry point: type and press Return to save a note without leaving the page.
struct NoteRow: View {
    let store: NotesStore
    @State private var draft = ""
    @State private var justSaved = false

    var body: some View {
        Card(padding: 0) {
            HStack(spacing: 8) {
                Image(systemName: justSaved ? "checkmark" : "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(justSaved ? Color.green : .white.opacity(0.45))
                    .frame(width: 14)
                TextField("Quick note", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .onSubmit(saveDraft)
                    .accessibilityLabel("Quick note")
                Button(action: store.open) {
                    HStack(spacing: 3) {
                        if !store.notes.isEmpty { Text("\(store.notes.count)") }
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help("All notes")
                .accessibilityLabel("Open notes")
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .frame(maxHeight: .infinity)
        }
        // Closing the notch or opening the full editor keeps whatever was typed.
        .onDisappear(perform: saveDraft)
    }

    private func saveDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add(text)
        draft = ""
        justSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSaved = false }
    }
}
