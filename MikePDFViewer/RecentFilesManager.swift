import Foundation

class RecentFilesManager: ObservableObject {
    @Published var recentURLs: [URL] = []

    private let key = "recentPDFFiles"
    private let bookmarksKey = "recentPDFBookmarks"
    private let maxRecent = 10

    // Sandboxed apps lose access to a file once the app relaunches unless a
    // security-scoped bookmark was saved while the user-granted access was
    // still valid. Bookmarks are stored path-keyed so recents survive relaunch.
    private var bookmarks: [String: Data] = [:]
    // URLs whose security scope we started this session; scope stays open for
    // the app's lifetime because PDFView reads page data lazily.
    private var accessedPaths: Set<String> = []

    init() {
        load()
    }

    func add(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > maxRecent {
            recentURLs = Array(recentURLs.prefix(maxRecent))
        }
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarks[url.path] = bookmark
        }
        save()
    }

    func clear() {
        recentURLs.removeAll()
        bookmarks.removeAll()
        save()
    }

    /// Resolves the stored security-scoped bookmark for a recent file and
    /// starts accessing it, so the sandboxed app can read the file even after
    /// a relaunch. Returns the URL to open (resolved when a bookmark exists,
    /// the original otherwise).
    func beginAccess(_ url: URL) -> URL {
        guard let bookmark = bookmarks[url.path] else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return url }

        if !accessedPaths.contains(resolved.path) {
            if resolved.startAccessingSecurityScopedResource() {
                accessedPaths.insert(resolved.path)
            }
        }
        if isStale, let fresh = try? resolved.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarks[resolved.path] = fresh
            save()
        }
        return resolved
    }

    /// The most recent file that can still be opened, for reopen-on-launch.
    /// Resolves the security-scoped bookmark first; without that, existence
    /// checks outside the sandbox container fail even for files that exist.
    var mostRecentExistingURL: URL? {
        for url in recentURLs {
            let resolved = beginAccess(url)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        return nil
    }

    private func save() {
        let paths = recentURLs.map { $0.path }
        UserDefaults.standard.set(paths, forKey: key)
        let validPaths = Set(paths)
        bookmarks = bookmarks.filter { validPaths.contains($0.key) }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func load() {
        if let stored = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] {
            bookmarks = stored
        }
        guard let paths = UserDefaults.standard.stringArray(forKey: key) else { return }
        recentURLs = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            // Entries with a bookmark are kept without an existence check:
            // the sandbox blocks stat() on outside paths until the bookmark
            // is resolved, so fileExists would wrongly discard them here.
            if bookmarks[path] != nil { return url }
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }
}
