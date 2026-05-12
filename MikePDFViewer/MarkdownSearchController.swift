import Foundation
import WebKit

/// Find-in-page driver for `MarkdownReaderView`. Lives outside the view so a
/// host can hold a single instance, hand it to the view, and call find methods
/// from anywhere (toolbar buttons, keyboard shortcuts, command menu items).
///
/// Each call to `find` / `findNext` / `findPrev` issues a WKWebView `find(_:)`
/// which scrolls to and highlights the next/previous match using the system's
/// built-in find machinery — same UI as the Find bar in Safari.
///
/// `findNext` and `findPrev` reuse the last query. `clear` removes the
/// highlight overlay so the document looks unsearched again.
@MainActor
public final class MarkdownSearchController: ObservableObject {

    /// Set by `MarkdownReaderView` when it appears. Cleared on disappear.
    /// Package-internal so external hosts can't bypass the view to drive find.
    weak var webView: WKWebView?

    /// Last query the host issued — used by `findNext` / `findPrev`.
    @Published public private(set) var lastQuery: String = ""

    /// Most recent find result (whether a match was reached). UI can dim the
    /// search field red if false.
    @Published public private(set) var lastResult: Result = .idle

    public enum Result: Equatable, Sendable {
        case idle
        case match
        case noMatch
    }

    public init() {}

    /// Find first match for a fresh query (or continue from current cursor if
    /// the query hasn't changed).
    public func find(_ query: String, caseSensitive: Bool = false) {
        run(query: query, backwards: false, caseSensitive: caseSensitive, wraps: true)
    }

    /// Advance to the next match of the most recent query.
    public func findNext(caseSensitive: Bool = false) {
        guard !lastQuery.isEmpty else { return }
        run(query: lastQuery, backwards: false, caseSensitive: caseSensitive, wraps: true)
    }

    /// Step back to the previous match of the most recent query.
    public func findPrev(caseSensitive: Bool = false) {
        guard !lastQuery.isEmpty else { return }
        run(query: lastQuery, backwards: true, caseSensitive: caseSensitive, wraps: true)
    }

    /// Remove any active find highlight from the document.
    public func clear() {
        lastQuery = ""
        lastResult = .idle
        guard let webView = webView else { return }
        // The cancel API is not directly exposed; setting an empty find call
        // with a guaranteed-unmatchable query effectively dismisses the overlay.
        let cfg = WKFindConfiguration()
        webView.find("\u{0001}__mike_clear_find__\u{0001}", configuration: cfg) { _ in }
    }

    private func run(query: String, backwards: Bool, caseSensitive: Bool, wraps: Bool) {
        guard !query.isEmpty else {
            clear()
            return
        }
        lastQuery = query
        guard let webView = webView else {
            lastResult = .idle
            return
        }
        let cfg = WKFindConfiguration()
        cfg.backwards = backwards
        cfg.caseSensitive = caseSensitive
        cfg.wraps = wraps
        webView.find(query, configuration: cfg) { [weak self] result in
            Task { @MainActor in
                self?.lastResult = result.matchFound ? .match : .noMatch
            }
        }
    }
}
