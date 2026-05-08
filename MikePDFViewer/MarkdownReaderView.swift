import SwiftUI
import WebKit
import AppKit

/// Whether the .md viewer is showing the new WKWebView-styled Reader or the
/// legacy NSTextView Quick view. Persisted across launches in v6 phase 3+;
/// for the MVP it lives only in @State.
enum MarkdownMode: String, CaseIterable {
    case reader
    case quick

    var displayName: String {
        switch self {
        case .reader: return "Reader"
        case .quick:  return "Quick"
        }
    }
}

/// WKWebView-based reader for markdown documents. Renders the source through
/// MarkdownToHTML, wraps it in a styled HTML template, and displays it in a
/// scrollable web view. Anchor links scroll within the document; external
/// links open in the browser.
///
/// This is the v6 "Reader" mode. The legacy NSTextView-based MarkdownView is
/// retained for the fallback "Quick" mode.
struct MarkdownReaderView: NSViewRepresentable {
    let source: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        loadContent(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedSource != source {
            loadContent(into: webView)
        }
    }

    private func loadContent(into webView: WKWebView) {
        let body = MarkdownToHTML.renderHTML(source)
        let html = MarkdownReaderTheme.githubLikeHTML(body: body, title: baseURL?.lastPathComponent ?? "Markdown")
        webView.loadHTMLString(html, baseURL: nil)
        if let coord = webView.navigationDelegate as? Coordinator {
            coord.lastRenderedSource = source
        }
    }

    /// Intercepts navigation: in-document `#anchor` jumps stay in-page, external
    /// http(s) and mailto open in the user's default browser, file:// requests
    /// are blocked (we never want WebView following arbitrary local paths).
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastRenderedSource: String = ""

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Initial loadHTMLString navigation has scheme "about" — allow.
            if navigationAction.navigationType == .other && url.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            // Same-document anchor jumps — let WebKit handle them natively.
            if url.fragment != nil, navigationAction.navigationType == .linkActivated,
               url.scheme == "applewebdata" || url.host == nil {
                decisionHandler(.allow)
                return
            }

            // External http(s) and mailto open in default app.
            if let scheme = url.scheme,
               scheme == "http" || scheme == "https" || scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // Block everything else (file://, app schemes, etc.).
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// CSS theme bundle. v6 MVP has one theme (GitHub-like) inline. Phase 3 will
/// expand to the six themes from the v6 plan.
enum MarkdownReaderTheme {

    static func githubLikeHTML(body: String, title: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(MarkdownToHTML.htmlEscape(title))</title>
            <style>\(githubLikeCSS)</style>
        </head>
        <body>
            <article class="markdown-body">
        \(body)
            </article>
        </body>
        </html>
        """
    }

    /// GitHub-style markdown CSS. Adapted from sindresorhus/github-markdown-css
    /// (MIT) — simplified to a single light theme for the MVP. Phase 3 swaps
    /// this for a CSS-variable-driven multi-theme system.
    private static let githubLikeCSS: String = """
    :root {
        color-scheme: light;
        --md-text: #24292f;
        --md-bg: #ffffff;
        --md-muted: #57606a;
        --md-border: #d0d7de;
        --md-border-muted: #d8dee4;
        --md-link: #0969da;
        --md-code-bg: #f6f8fa;
        --md-code-text: #1f2328;
        --md-quote-border: #d0d7de;
        --md-table-stripe: #f6f8fa;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            color-scheme: dark;
            --md-text: #e6edf3;
            --md-bg: #0d1117;
            --md-muted: #8b949e;
            --md-border: #30363d;
            --md-border-muted: #21262d;
            --md-link: #2f81f7;
            --md-code-bg: #161b22;
            --md-code-text: #e6edf3;
            --md-quote-border: #30363d;
            --md-table-stripe: #161b22;
        }
    }
    html, body {
        margin: 0;
        padding: 0;
        background: var(--md-bg);
        color: var(--md-text);
    }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue",
                     Helvetica, Arial, sans-serif;
        font-size: 16px;
        line-height: 1.6;
        -webkit-font-smoothing: antialiased;
        word-wrap: break-word;
    }
    .markdown-body {
        max-width: 820px;
        margin: 0 auto;
        padding: 40px 56px 80px;
    }
    .markdown-body > *:first-child { margin-top: 0; }
    .markdown-body h1,
    .markdown-body h2,
    .markdown-body h3,
    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        margin-top: 24px;
        margin-bottom: 16px;
        font-weight: 600;
        line-height: 1.25;
    }
    .markdown-body h1 {
        font-size: 2em;
        border-bottom: 1px solid var(--md-border-muted);
        padding-bottom: 0.3em;
    }
    .markdown-body h2 {
        font-size: 1.5em;
        border-bottom: 1px solid var(--md-border-muted);
        padding-bottom: 0.3em;
    }
    .markdown-body h3 { font-size: 1.25em; }
    .markdown-body h4 { font-size: 1em; }
    .markdown-body h5 { font-size: 0.875em; }
    .markdown-body h6 { font-size: 0.85em; color: var(--md-muted); }
    .markdown-body p {
        margin-top: 0;
        margin-bottom: 16px;
    }
    .markdown-body a {
        color: var(--md-link);
        text-decoration: none;
    }
    .markdown-body a:hover { text-decoration: underline; }
    .markdown-body strong { font-weight: 600; }
    .markdown-body em { font-style: italic; }
    .markdown-body code {
        font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
                     "Liberation Mono", monospace;
        font-size: 85%;
        background: var(--md-code-bg);
        color: var(--md-code-text);
        padding: 0.2em 0.4em;
        border-radius: 6px;
    }
    .markdown-body pre {
        font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
                     "Liberation Mono", monospace;
        font-size: 85%;
        background: var(--md-code-bg);
        color: var(--md-code-text);
        padding: 16px;
        overflow: auto;
        border-radius: 6px;
        line-height: 1.45;
        margin-top: 0;
        margin-bottom: 16px;
    }
    .markdown-body pre code {
        background: transparent;
        padding: 0;
        font-size: inherit;
        border-radius: 0;
    }
    .markdown-body blockquote {
        margin: 0 0 16px 0;
        padding: 0 1em;
        color: var(--md-muted);
        border-left: 0.25em solid var(--md-quote-border);
    }
    .markdown-body ul,
    .markdown-body ol {
        margin-top: 0;
        margin-bottom: 16px;
        padding-left: 2em;
    }
    .markdown-body ul ul, .markdown-body ul ol,
    .markdown-body ol ul, .markdown-body ol ol {
        margin-bottom: 0;
    }
    .markdown-body li { margin: 0.25em 0; }
    .markdown-body li > p { margin-top: 16px; }
    .markdown-body hr {
        border: 0;
        height: 0.25em;
        background: var(--md-border-muted);
        margin: 24px 0;
    }
    .markdown-body table {
        border-collapse: collapse;
        margin-top: 0;
        margin-bottom: 16px;
        display: block;
        overflow: auto;
        max-width: 100%;
    }
    .markdown-body table th,
    .markdown-body table td {
        padding: 6px 13px;
        border: 1px solid var(--md-border);
    }
    .markdown-body table th { font-weight: 600; }
    .markdown-body table tr:nth-child(2n) {
        background: var(--md-table-stripe);
    }
    .markdown-body img { max-width: 100%; box-sizing: content-box; }
    .markdown-body kbd {
        display: inline-block;
        padding: 3px 5px;
        font-family: ui-monospace, SFMono-Regular, monospace;
        font-size: 11px;
        line-height: 10px;
        color: var(--md-text);
        vertical-align: middle;
        background: var(--md-bg);
        border: solid 1px var(--md-border);
        border-bottom-color: var(--md-border);
        border-radius: 6px;
        box-shadow: inset 0 -1px 0 var(--md-border);
    }
    """
}
