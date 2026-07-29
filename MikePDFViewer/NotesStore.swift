import Foundation
import AppKit

// MARK: - Word counting

/// Linguistic word counter (same style as Apple's apps): counts words, not
/// whitespace runs, so punctuation and blank lines never inflate the number.
enum WordCounter {
    static func words(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

// MARK: - Note model

/// One notepad note. The whole store round-trips through pretty-printed JSON
/// so tools outside the app (search, indexing, RAG pipelines) can read it
/// directly; title and wordCount are persisted for that reason even though
/// the app could recompute them.
struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var modifiedAt: Date
    var wordCount: Int

    init(body: String = "") {
        self.id = UUID()
        self.body = body
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.title = Note.deriveTitle(from: body)
        self.wordCount = WordCounter.words(in: body)
    }

    /// Apple Notes style: the first non-empty line is the title.
    static func deriveTitle(from body: String) -> String {
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty ? "New Note" : String(firstLine.prefix(80))
    }
}

// MARK: - Store

/// Loads and saves all notes as one JSON file:
///   <container>/Documents/Notes/notes.json
/// Saves are debounced while typing and flushed on quit.
@MainActor
final class NotesManager: ObservableObject {

    static let shared = NotesManager()

    @Published private(set) var notes: [Note] = []

    private var saveTask: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?

    static var notesFolderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Notes", isDirectory: true)
    }

    static var notesFileURL: URL {
        notesFolderURL.appendingPathComponent("notes.json")
    }

    private init() {
        load()
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: CRUD

    /// Insert a fresh empty note at the top and return its id for selection.
    func newNote() -> UUID {
        let note = Note()
        notes.insert(note, at: 0)
        scheduleSave()
        return note.id
    }

    func note(with id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    func updateBody(id: UUID, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].body != body else { return }
        notes[index].body = body
        notes[index].title = Note.deriveTitle(from: body)
        notes[index].wordCount = WordCounter.words(in: body)
        notes[index].modifiedAt = Date()
        scheduleSave()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Persistence

    private struct StoreFile: Codable {
        var version: Int
        var notes: [Note]
    }

    private func load() {
        guard let data = try? Data(contentsOf: NotesManager.notesFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(StoreFile.self, from: data) {
            // Newest first, matching how new notes are inserted.
            notes = file.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    /// Debounce so every keystroke doesn't hit the disk.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: NotesManager.notesFolderURL,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(StoreFile(version: 1, notes: notes))
            try data.write(to: NotesManager.notesFileURL, options: .atomic)
        } catch {
            NSLog("NotesManager save failed: \(error.localizedDescription)")
        }
    }

    func revealInFinder() {
        saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([NotesManager.notesFileURL])
    }
}
