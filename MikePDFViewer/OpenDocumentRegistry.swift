import SwiftUI
import AppKit

/// Tracks which window is showing which file, so opening a document that is
/// already open can raise that window instead of loading a second copy.
///
/// Windows are held weakly and pruned on every lookup: a closed window simply
/// disappears from the registry without needing a teardown callback to fire.
@MainActor
final class OpenDocumentRegistry {
    static let shared = OpenDocumentRegistry()

    private struct Entry {
        weak var window: NSWindow?
        var url: URL?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Symlinks and "/./" segments resolved, so /tmp/x.pdf and /private/tmp/x.pdf
    /// are recognized as the same document.
    static func key(for url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Record (or clear) the document a window is currently showing.
    func update(url: URL?, for window: NSWindow?) {
        prune()
        guard let window else { return }
        entries[ObjectIdentifier(window)] = Entry(window: window,
                                                  url: url.map(Self.key(for:)))
    }

    func forget(_ window: NSWindow?) {
        guard let window else { return }
        entries.removeValue(forKey: ObjectIdentifier(window))
        prune()
    }

    /// The window already displaying `url`, ignoring `excluding` (the window
    /// that is asking). Returns nil when no other window has it open.
    func window(showing url: URL, excluding: NSWindow?) -> NSWindow? {
        prune()
        let target = Self.key(for: url)
        let excludedID = excluding.map { ObjectIdentifier($0) }
        for (id, entry) in entries {
            guard id != excludedID,
                  let window = entry.window,
                  entry.url == target else { continue }
            return window
        }
        return nil
    }

    private func prune() {
        entries = entries.filter { $0.value.window != nil }
    }
}

/// Reports the NSWindow hosting a SwiftUI view. SwiftUI has no first-class
/// access to it, and the window is not attached yet when makeNSView runs, so
/// the callback is deferred a runloop turn.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
