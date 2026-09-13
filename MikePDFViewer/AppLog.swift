import Foundation

/// Append-only diagnostic log so problems can be read from disk instead of
/// reproduced by hand. Lives at <container>/Documents/logs/mikepdfviewer.log
/// (Settings > General has a Reveal button). Writes are serialized off the
/// main thread; failures to write are ignored.
enum AppLog {
    private static let queue = DispatchQueue(label: "com.mikeashe.MikePDFViewer.AppLog")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("mikepdfviewer.log")
    }

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            let url = fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
