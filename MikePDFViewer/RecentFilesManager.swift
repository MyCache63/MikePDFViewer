import Foundation

class RecentFilesManager: ObservableObject {
    @Published var recentURLs: [URL] = []

    private let key = "recentPDFFiles"
    private let maxRecent = 10

    init() {
        load()
    }

    func add(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > maxRecent {
            recentURLs = Array(recentURLs.prefix(maxRecent))
        }
        save()
    }

    func clear() {
        recentURLs.removeAll()
        save()
    }

    private func save() {
        let paths = recentURLs.map { $0.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    private func load() {
        guard let paths = UserDefaults.standard.stringArray(forKey: key) else { return }
        recentURLs = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }
}
