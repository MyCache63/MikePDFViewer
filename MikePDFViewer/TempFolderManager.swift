import Foundation

/// Owns ~/Documents/MikePDFViewer/tmp/ — the staging area for rendered MD/DOCX→PDF
/// output. Files older than 7 days are purged on app launch.
enum TempFolderManager {

    static let folderName = "MikePDFViewer"
    static let tmpSubfolder = "tmp"
    static let maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    /// Path to the temp folder, creating it if needed.
    static var tmpFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent(folderName).appendingPathComponent(tmpSubfolder)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Build a unique destination URL for a rendered PDF based on the source filename.
    /// Format: <basename>_<yyyyMMdd-HHmmss>.pdf, with collision suffix if needed.
    static func destinationURL(for sourceURL: URL, ext: String = "pdf") -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        var candidate = tmpFolder.appendingPathComponent("\(base)_\(stamp).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = tmpFolder.appendingPathComponent("\(base)_\(stamp)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// Write data to a fresh temp URL and return the URL.
    static func writeToTemp(data: Data, sourceURL: URL, ext: String = "pdf") throws -> URL {
        let dest = destinationURL(for: sourceURL, ext: ext)
        try data.write(to: dest)
        return dest
    }

    /// Delete files in tmp older than `maxAgeSeconds`. Safe to call repeatedly.
    static func purgeOldFiles() {
        let folder = tmpFolder
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-maxAgeSeconds)
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            if modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Manually clear all files in the temp folder.
    static func clearAll() {
        let folder = tmpFolder
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
