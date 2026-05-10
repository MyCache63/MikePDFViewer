import Foundation

/// Owns the base directory used to stage rendered PDFs from MD/DOCX/EML
/// conversions. Files older than `maxAgeDays` are purged on app launch.
///
/// Host apps can override `baseDirectory` to point the kit at their own
/// scratch area. The standalone MikePDFViewer.app sets this to its
/// container Documents/MikePDFViewer/tmp/; embedding hosts (e.g. Mission
/// Control) can leave the default `NSTemporaryDirectory/MikePDFViewerKit/`
/// or point it elsewhere.
public enum TempFolderManager {

    /// Days to retain a file in the temp folder before automatic purge.
    public static var maxAgeDays: Int = 7

    /// Base directory for rendered temp PDFs. Default is the system temp
    /// directory plus a "MikePDFViewerKit" subfolder so hosts that don't
    /// configure anything still get a tidy location.
    public static var baseDirectory: URL = {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MikePDFViewerKit", isDirectory: true)
    }()

    /// Resolved temp folder, creating it on demand.
    public static var tmpFolder: URL {
        if !FileManager.default.fileExists(atPath: baseDirectory.path) {
            try? FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        }
        return baseDirectory
    }

    /// Build a unique destination URL for a rendered file based on the source
    /// filename. Format: `<basename>_<yyyyMMdd-HHmmss>.<ext>` with a counter
    /// suffix if needed to avoid collisions.
    public static func destinationURL(for sourceURL: URL, ext: String = "pdf") -> URL {
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
    public static func writeToTemp(data: Data, sourceURL: URL, ext: String = "pdf") throws -> URL {
        let dest = destinationURL(for: sourceURL, ext: ext)
        try data.write(to: dest)
        return dest
    }

    /// Delete files in the temp folder older than `maxAgeDays`. Safe to call repeatedly.
    public static func purgeOldFiles() {
        let folder = tmpFolder
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            if modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Manually clear all files in the temp folder.
    public static func clearAll() {
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
