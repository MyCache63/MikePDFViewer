import SwiftUI

// MARK: - Yellow lined notebook icon (drawn, no asset needed)

struct NotepadIconView: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1.00, green: 0.90, blue: 0.42),
                             Color(red: 0.98, green: 0.80, blue: 0.25)],
                    startPoint: .top, endPoint: .bottom))
            // Ruled lines
            VStack(spacing: size * 0.16) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(red: 0.35, green: 0.45, blue: 0.65).opacity(0.55))
                        .frame(height: max(0.7, size * 0.05))
                }
            }
            .padding(.horizontal, size * 0.16)
            .offset(y: size * 0.08)
            // Red margin line, legal-pad style
            Rectangle()
                .fill(Color(red: 0.85, green: 0.30, blue: 0.22).opacity(0.8))
                .frame(width: max(0.7, size * 0.05))
                .offset(x: -size * 0.28)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Notepad window

struct NotepadView: View {
    @ObservedObject private var store = NotesManager.shared
    @State private var selectedID: UUID?
    @State private var searchText: String = ""
    @State private var pendingDeleteID: UUID?
    @AppStorage("notepad-font-size") private var fontSize: Double = 14

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedNote: Note? {
        selectedID.flatMap { store.note(with: $0) }
    }

    var body: some View {
        NavigationSplitView {
            noteList
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 350)
        } detail: {
            detailPane
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
        .frame(minWidth: 640, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    selectedID = store.newNote()
                    searchText = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Note")
            }
            ToolbarItem {
                Button {
                    if let id = selectedID { pendingDeleteID = id }
                } label: {
                    Image(systemName: "trash")
                }
                .tooltip("Delete Note")
                .disabled(selectedID == nil)
            }
        }
        .confirmationDialog(
            "Delete \"\(pendingDeleteID.flatMap { store.note(with: $0)?.title } ?? "note")\"?",
            isPresented: Binding(get: { pendingDeleteID != nil },
                                 set: { if !$0 { pendingDeleteID = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID {
                    store.delete(id: id)
                    if selectedID == id { selectedID = store.notes.first?.id }
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This removes the note from notes.json. This can't be undone.")
        }
        .onAppear {
            if selectedID == nil { selectedID = store.notes.first?.id }
        }
        .onDisappear {
            store.saveNow()
        }
    }

    private var noteList: some View {
        List(selection: $selectedID) {
            ForEach(filteredNotes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack {
                        Text(note.modifiedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Spacer()
                        Text("\(note.wordCount) words")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(note.id)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let note = selectedNote {
            VStack(spacing: 0) {
                TextEditor(text: bodyBinding(for: note.id))
                    .font(.system(size: fontSize))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                Divider()
                statusBar(for: note)
            }
        } else {
            VStack(spacing: 10) {
                NotepadIconView(size: 44)
                Text("Select a note or create a new one")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The word count function: live words / characters / lines for the open
    /// note, always visible at the bottom of the editor.
    private func statusBar(for note: Note) -> some View {
        HStack(spacing: 14) {
            Text("\(note.wordCount) words")
                .fontWeight(.medium)
            Text("\(note.body.count) characters")
            Text("\(note.body.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
            Spacer()
            Stepper("Text size", value: $fontSize, in: 10...24, step: 1)
                .labelsHidden()
                .help("Text size")
            Button {
                store.revealInFinder()
            } label: {
                Label("notes.json", systemImage: "folder")
            }
            .buttonStyle(.link)
            .help("Notes are stored as JSON so other tools can search or index them. Click to reveal notes.json in Finder.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func bodyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.note(with: id)?.body ?? "" },
            set: { store.updateBody(id: id, body: $0) }
        )
    }
}
