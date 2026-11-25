import AppKit
import SwiftUI

enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case yellow, pink, blue, green, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: Color(red: 1.0, green: 0.84, blue: 0.25)
        case .pink: Color(red: 1.0, green: 0.45, blue: 0.6)
        case .blue: Color(red: 0.35, green: 0.65, blue: 1.0)
        case .green: Color(red: 0.4, green: 0.85, blue: 0.5)
        case .purple: Color(red: 0.7, green: 0.5, blue: 1.0)
        }
    }
}

struct Note: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var color: NoteColor
    /// Pinned notes are "important": they stay at the top of the list.
    var isPinned: Bool
    var updatedAt: Date

    /// First non-empty line, shortened.
    var title: String {
        let line = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return "New Note" }
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }
}

/// Sticky notes, saved as JSON in ~/Library/Application Support/NotchIsland/notes.json.
/// Notes never leave this Mac.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?
    private var terminateObserver: NSObjectProtocol?

    init(directory: URL? = nil) {
        let folder = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland", isDirectory: true)
        fileURL = folder.appendingPathComponent("notes.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = Self.sorted(saved)
        }
        selectedID = notes.first?.id

        // Write any pending edit before the app quits.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    var selected: Note? {
        notes.first { $0.id == selectedID }
    }

    func note(_ id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func add(color: NoteColor? = nil) -> Note {
        // Cycle colors so new notes are easy to tell apart.
        let nextColor = color ?? NoteColor.allCases[notes.count % NoteColor.allCases.count]
        let note = Note(id: UUID(), text: "", color: nextColor, isPinned: false, updatedAt: Date())
        notes = Self.sorted(notes + [note])
        selectedID = note.id
        scheduleSave()
        return note
    }

    func updateText(_ id: UUID, _ text: String) {
        mutate(id) { $0.text = text }
    }

    func togglePin(_ id: UUID) {
        mutate(id) { $0.isPinned.toggle() }
    }

    func setColor(_ id: UUID, _ color: NoteColor) {
        mutate(id) { $0.color = color }
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if selectedID == id {
            selectedID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        scheduleSave()
    }

    private func mutate(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        change(&note)
        guard note != notes[index] else { return }
        note.updatedAt = Date()
        notes[index] = note
        notes = Self.sorted(notes)
        scheduleSave()
    }

    /// Pinned first, then most recently edited.
    nonisolated static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Saving

    /// Saves half a second after the last change, so typing doesn't write on every key.
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NotchIsland: could not save notes: \(error.localizedDescription)")
        }
    }
}
