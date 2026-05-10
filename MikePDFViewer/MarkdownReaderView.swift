import SwiftUI
import WebKit
import AppKit

/// Whether the .md viewer is showing the new WKWebView-styled Reader or the
/// legacy NSTextView Quick view. Persisted across launches in v6 phase 3+;
/// for the MVP it lives only in @State.
public enum MarkdownMode: String, CaseIterable {
    case reader
    case quick

    public var displayName: String {
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
public struct MarkdownReaderView: NSViewRepresentable {
    public let source: String
    public let baseURL: URL?
    public let theme: MarkdownReaderTheme

    public init(source: String, baseURL: URL?, theme: MarkdownReaderTheme = .github) {
        self.source = source
        self.baseURL = baseURL
        self.theme = theme
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> WKWebView {
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

    public func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedSource != source
            || context.coordinator.lastTheme != theme {
            loadContent(into: webView)
        }
    }

    private func loadContent(into webView: WKWebView) {
        let body = MarkdownToHTML.renderHTML(source)
        let html = MarkdownReaderThemeBundle.html(body: body,
                                                   title: baseURL?.lastPathComponent ?? "Markdown",
                                                   theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
        if let coord = webView.navigationDelegate as? Coordinator {
            coord.lastRenderedSource = source
            coord.lastTheme = theme
        }
    }

    /// Intercepts navigation: in-document `#anchor` jumps stay in-page, external
    /// http(s) and mailto open in the user's default browser, file:// requests
    /// are blocked (we never want WebView following arbitrary local paths).
    public final class Coordinator: NSObject, WKNavigationDelegate {
        var lastRenderedSource: String = ""
        var lastTheme: MarkdownReaderTheme = .github

        public func webView(_ webView: WKWebView,
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

/// Available reading themes. Each maps to a CSS bundle in
/// MarkdownReaderThemeBundle. Persisted by host app via UserDefaults using
/// the `rawValue` String.
public enum MarkdownReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case github       // GitHub-style, follows system light/dark
    case newsprint    // serif, narrow column, warm paper
    case sepia        // warm e-reader feel
    case dark         // dark background, off-white text
    case highContrast // pure black on white, larger spacing
    case mono         // monospace everywhere, iA-Writer-like

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .github:       return "GitHub"
        case .newsprint:    return "Newsprint"
        case .sepia:        return "Sepia"
        case .dark:         return "Dark"
        case .highContrast: return "High Contrast"
        case .mono:         return "Mono"
        }
    }
}

/// CSS bundle resolver. Each theme is a self-contained stylesheet rendered
/// inside the same `<article class="markdown-body">` shell, so theme switches
/// don't require parsing changes.
enum MarkdownReaderThemeBundle {

    static func html(body: String, title: String, theme: MarkdownReaderTheme) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(MarkdownToHTML.htmlEscape(title))</title>
            <style>\(css(for: theme))</style>
        </head>
        <body>
            <article class="markdown-body">
        \(body)
            </article>
        </body>
        </html>
        """
    }

    private static func css(for theme: MarkdownReaderTheme) -> String {
        switch theme {
        case .github:       return githubCSS
        case .newsprint:    return newsprintCSS
        case .sepia:        return sepiaCSS
        case .dark:         return darkCSS
        case .highContrast: return highContrastCSS
        case .mono:         return monoCSS
        }
    }

    /// Common skeleton: typography variables + structural rules. Each theme
    /// overrides the variable values and any extra rules.
    private static let baseCSS: String = """
    :root {
        --md-font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue",
                          Helvetica, Arial, sans-serif;
        --md-mono-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
                          "Liberation Mono", monospace;
        --md-font-size: 16px;
        --md-line-height: 1.6;
        --md-content-width: 820px;
        --md-content-padding: 40px 56px 80px;
    }
    html, body {
        margin: 0;
        padding: 0;
        background: var(--md-bg);
        color: var(--md-text);
    }
    body {
        font-family: var(--md-font-family);
        font-size: var(--md-font-size);
        line-height: var(--md-line-height);
        -webkit-font-smoothing: antialiased;
        word-wrap: break-word;
    }
    .markdown-body {
        max-width: var(--md-content-width);
        margin: 0 auto;
        padding: var(--md-content-padding);
    }
    .markdown-body > *:first-child { margin-top: 0; }
    .markdown-body h1, .markdown-body h2, .markdown-body h3,
    .markdown-body h4, .markdown-body h5, .markdown-body h6 {
        margin-top: 24px;
        margin-bottom: 16px;
        font-weight: 600;
        line-height: 1.25;
    }
    .markdown-body h1 { font-size: 2em; border-bottom: 1px solid var(--md-border-muted); padding-bottom: 0.3em; }
    .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid var(--md-border-muted); padding-bottom: 0.3em; }
    .markdown-body h3 { font-size: 1.25em; }
    .markdown-body h4 { font-size: 1em; }
    .markdown-body h5 { font-size: 0.875em; }
    .markdown-body h6 { font-size: 0.85em; color: var(--md-muted); }
    .markdown-body p { margin-top: 0; margin-bottom: 16px; }
    .markdown-body a { color: var(--md-link); text-decoration: none; }
    .markdown-body a:hover { text-decoration: underline; }
    .markdown-body strong { font-weight: 600; }
    .markdown-body em { font-style: italic; }
    .markdown-body code {
        font-family: var(--md-mono-family);
        font-size: 85%;
        background: var(--md-code-bg);
        color: var(--md-code-text);
        padding: 0.2em 0.4em;
        border-radius: 6px;
    }
    .markdown-body pre {
        font-family: var(--md-mono-family);
        font-size: 85%;
        background: var(--md-code-bg);
        color: var(--md-code-text);
        padding: 16px;
        overflow: auto;
        border-radius: 6px;
        line-height: 1.45;
        margin: 0 0 16px 0;
    }
    .markdown-body pre code { background: transparent; padding: 0; font-size: inherit; border-radius: 0; }
    .markdown-body blockquote {
        margin: 0 0 16px 0;
        padding: 0 1em;
        color: var(--md-muted);
        border-left: 0.25em solid var(--md-quote-border);
    }
    .markdown-body ul, .markdown-body ol { margin: 0 0 16px 0; padding-left: 2em; }
    .markdown-body ul ul, .markdown-body ul ol,
    .markdown-body ol ul, .markdown-body ol ol { margin-bottom: 0; }
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
        margin: 0 0 16px 0;
        display: block;
        overflow: auto;
        max-width: 100%;
    }
    .markdown-body table th, .markdown-body table td {
        padding: 6px 13px;
        border: 1px solid var(--md-border);
    }
    .markdown-body table th { font-weight: 600; }
    .markdown-body table tr:nth-child(2n) { background: var(--md-table-stripe); }
    .markdown-body img { max-width: 100%; box-sizing: content-box; }
    """

    // MARK: - GitHub theme (default; follows system light/dark)
    private static var githubCSS: String { baseCSS + """

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
    """ }

    // MARK: - Newsprint theme (serif, narrow column, warm paper)
    private static var newsprintCSS: String { baseCSS + """

    :root {
        color-scheme: light;
        --md-font-family: "Iowan Old Style", "Palatino", Georgia, serif;
        --md-font-size: 17px;
        --md-line-height: 1.7;
        --md-content-width: 680px;
        --md-text: #2a2a2a;
        --md-bg: #f5f1e8;
        --md-muted: #6a6258;
        --md-border: #cdc5b3;
        --md-border-muted: #e0d9c8;
        --md-link: #8a4b08;
        --md-code-bg: #ece6d4;
        --md-code-text: #2a2a2a;
        --md-quote-border: #b8a984;
        --md-table-stripe: #ece6d4;
    }
    """ }

    // MARK: - Sepia theme (warm e-reader)
    private static var sepiaCSS: String { baseCSS + """

    :root {
        color-scheme: light;
        --md-font-family: "Iowan Old Style", "Palatino", Georgia, serif;
        --md-font-size: 17px;
        --md-line-height: 1.7;
        --md-content-width: 720px;
        --md-text: #5b4636;
        --md-bg: #f4ecd8;
        --md-muted: #8a7053;
        --md-border: #d6c7a3;
        --md-border-muted: #e6dcc1;
        --md-link: #a0521c;
        --md-code-bg: #ebe0c2;
        --md-code-text: #5b4636;
        --md-quote-border: #c2a878;
        --md-table-stripe: #ebe0c2;
    }
    """ }

    // MARK: - Dark theme (always-dark, regardless of system)
    private static var darkCSS: String { baseCSS + """

    :root {
        color-scheme: dark;
        --md-text: #d8dee4;
        --md-bg: #1c2128;
        --md-muted: #909dab;
        --md-border: #383f48;
        --md-border-muted: #2a3038;
        --md-link: #4493f8;
        --md-code-bg: #2a3038;
        --md-code-text: #e6edf3;
        --md-quote-border: #4a5560;
        --md-table-stripe: #232830;
    }
    """ }

    // MARK: - High contrast (pure black on white, more spacing)
    private static var highContrastCSS: String { baseCSS + """

    :root {
        color-scheme: light;
        --md-font-size: 18px;
        --md-line-height: 1.75;
        --md-text: #000000;
        --md-bg: #ffffff;
        --md-muted: #333333;
        --md-border: #000000;
        --md-border-muted: #000000;
        --md-link: #0000ee;
        --md-code-bg: #f0f0f0;
        --md-code-text: #000000;
        --md-quote-border: #000000;
        --md-table-stripe: #f0f0f0;
    }
    .markdown-body strong { font-weight: 700; }
    """ }

    // MARK: - Mono (monospace, iA-Writer-like)
    private static var monoCSS: String { baseCSS + """

    :root {
        color-scheme: light;
        --md-font-family: var(--md-mono-family);
        --md-font-size: 15px;
        --md-line-height: 1.65;
        --md-content-width: 720px;
        --md-text: #2a2a2a;
        --md-bg: #fafafa;
        --md-muted: #707070;
        --md-border: #d0d0d0;
        --md-border-muted: #e2e2e2;
        --md-link: #1a6cb6;
        --md-code-bg: #efefef;
        --md-code-text: #2a2a2a;
        --md-quote-border: #c0c0c0;
        --md-table-stripe: #efefef;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            color-scheme: dark;
            --md-text: #e0e0e0;
            --md-bg: #1a1a1a;
            --md-muted: #909090;
            --md-border: #3a3a3a;
            --md-border-muted: #2a2a2a;
            --md-link: #6ab1f7;
            --md-code-bg: #2a2a2a;
            --md-code-text: #e0e0e0;
            --md-quote-border: #4a4a4a;
            --md-table-stripe: #232323;
        }
    }
    """ }

}
