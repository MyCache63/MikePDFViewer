import Foundation

struct Bookmark: Codable, Identifiable {
    let id: UUID
    let pageIndex: Int
    var label: String
    let created: Date

    init(pageIndex: Int, label: String = "") {
        self.id = UUID()
        self.pageIndex = pageIndex
        self.label = label.isEmpty ? "Page \(pageIndex + 1)" : label
        self.created = Date()
    }
}

class BookmarkManager: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    private var fileKey: String = ""

    private static let storageKey = "pdfBookmarks"

    func load(for url: URL?) {
        guard let url else {
            bookmarks = []
            fileKey = ""
            return
        }
        fileKey = url.absoluteString
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let allBookmarks = try? JSONDecoder().decode([String: [Bookmark]].self, from: data) {
            bookmarks = allBookmarks[fileKey] ?? []
        } else {
            bookmarks = []
        }
    }

    func save() {
        guard !fileKey.isEmpty else { return }
        var allBookmarks = loadAll()
        allBookmarks[fileKey] = bookmarks
        if let data = try? JSONEncoder().encode(allBookmarks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func toggleBookmark(for pageIndex: Int) {
        if let index = bookmarks.firstIndex(where: { $0.pageIndex == pageIndex }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(Bookmark(pageIndex: pageIndex))
        }
        save()
    }

    func isBookmarked(_ pageIndex: Int) -> Bool {
        bookmarks.contains(where: { $0.pageIndex == pageIndex })
    }

    func renameBookmark(id: UUID, to label: String) {
        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index].label = label
            save()
        }
    }

    private func loadAll() -> [String: [Bookmark]] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let result = try? JSONDecoder().decode([String: [Bookmark]].self, from: data) else {
            return [:]
        }
        return result
    }
}
