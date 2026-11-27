import SwiftUI

/// Sticky notes: a list on the left, the selected note on the right.
struct NotesView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var notes: NotesStore
    @State private var editorFocused = false
    @State private var focusRequest = 0

    var body: some View {
        if notes.notes.isEmpty {
            WidgetMessage(symbol: "note.text",
                          title: "No notes yet",
                          message: "Jot down something important or a quick note.",
                          buttonTitle: "New Note",
                          action: addNote)
        } else {
            HStack(alignment: .top, spacing: 12) {
                noteList
                    .frame(width: 150)
                if let note = notes.selected {
                    editor(for: note)
                }
            }
        }
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NOTES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                IconButton(symbol: "plus", help: "New note", action: addNote)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(notes.notes) { note in
                        NoteRow(note: note, isSelected: note.id == notes.selectedID)
                            .onTapGesture { notes.selectedID = note.id }
                            .contextMenu { menu(for: note) }
                    }
                }
            }
        }
    }

    private func editor(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(NoteColor.allCases) { color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: note.color == color ? 1.5 : 0))
                        .contentShape(Circle().inset(by: -3))
                        .onTapGesture { notes.setColor(note.id, color) }
                        .compatHelp(color.rawValue.capitalized)
                }
                Spacer()
                IconButton(symbol: note.isPinned ? "pin.fill" : "pin",
                           help: note.isPinned ? "Unpin" : "Pin as important") {
                    notes.togglePin(note.id)
                }
                IconButton(symbol: "trash", help: "Delete note") {
                    notes.delete(note.id)
                }
            }

            PlainTextEditor(text: Binding(
                get: { notes.note(note.id)?.text ?? "" },
                set: { notes.updateText(note.id, $0) }
            ), focusRequest: focusRequest, onFocusChange: { editorFocused = $0 })
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(note.color.color.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(note.color.color.opacity(editorFocused ? 0.6 : 0.25), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        Button(note.isPinned ? "Unpin" : "Pin as Important") { notes.togglePin(note.id) }
        if #available(macOS 11, *) {
            Menu("Color") {
                ForEach(NoteColor.allCases) { color in
                    Button(color.rawValue.capitalized) { notes.setColor(note.id, color) }
                }
            }
        } else {
            ForEach(NoteColor.allCases) { color in
                Button("Color: \(color.rawValue.capitalized)") { notes.setColor(note.id, color) }
            }
        }
        Divider()
        Button("Delete Note") { notes.delete(note.id) }
    }

    private func addNote() {
        notes.add()
        DispatchQueue.main.async { focusRequest += 1 }
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(note.color.color)
                .frame(width: 7, height: 7)
            Text(note.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if note.isPinned {
                SymbolImage("pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.15 : 0))
        )
        .contentShape(Rectangle())
    }
}
