import SwiftUI
import WebKit

/// Mini browser for local .html files. Uses WKWebView (Safari's engine), so
/// pages render exactly as they do in Safari. Links are allowed to navigate
/// inside the view, including out to the web, with Back/Forward support.
@MainActor
final class HTMLBrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle = ""

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(fileURL: URL) {
        // Read access to the file's folder so relative images/CSS resolve.
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshState()
    }

    // target=_blank links: load in the same view instead of silently dropping.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

struct HTMLBrowserView: NSViewRepresentable {
    @ObservedObject var controller: HTMLBrowserController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - SVG rendering

/// Builds the page an .svg file is displayed on. SVG is XML that browsers
/// render natively, so WKWebView does the drawing and stays sharp at any zoom.
enum SVGPage {

    /// Interactive page used in the viewer: neutral background, centred
    /// drawing, and zoom driven from the toolbar through `window.__svgZoom`.
    static func html(svgSource: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; height: 100%; background: #ffffff; }
        @media (prefers-color-scheme: dark) { html, body { background: #1c1c1e; } }
        #stage { box-sizing: border-box; min-height: 100vh; padding: 16px;
                 display: flex; align-items: center; justify-content: center; }
        #holder svg { display: block; }
        </style></head><body>
        <div id="stage"><div id="holder">\(svgSource)</div></div>
        <script>
        (function () {
          var holder = document.getElementById('holder');
          var svg = holder.querySelector('svg');
          var scale = 1;
          var fitScale = 1;
          var size = { w: 0, h: 0 };
          function measure() {
            if (!svg) { return; }
            var box = svg.viewBox && svg.viewBox.baseVal;
            if (box && box.width > 0) { size = { w: box.width, h: box.height }; return; }
            var rect = svg.getBoundingClientRect();
            size = { w: rect.width, h: rect.height };
          }
          function apply() {
            if (!svg || size.w <= 0) { return; }
            svg.setAttribute('width', size.w * scale);
            svg.setAttribute('height', size.h * scale);
          }
          function fit() {
            if (size.w <= 0) { return; }
            var room = Math.min((window.innerWidth - 44) / size.w,
                                (window.innerHeight - 44) / size.h);
            fitScale = Math.max(0.05, Math.min(room, 40));
            scale = fitScale;
            apply();
          }
          window.__svgSetScale = function (value) {
            scale = Math.max(0.02, Math.min(fitScale * value, 40));
            apply();
          };
          window.__svgZoom = function (action) {
            if (action === 'fit') { fit(); return; }
            if (action === 'actual') { scale = 1; }
            if (action === 'in') { scale = Math.min(scale * 1.25, 40); }
            if (action === 'out') { scale = Math.max(scale / 1.25, 0.05); }
            apply();
          };
          measure();
          fit();
        })();
        </script></body></html>
        """
    }

    /// Static page for export and printing. The paginated renderer runs with
    /// JavaScript off, so the fit here is pure CSS.
    static func staticHTML(svgSource: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; background: #ffffff; }
        #holder { display: flex; align-items: center; justify-content: center; }
        #holder svg { display: block; max-width: 100%; height: auto; }
        </style></head><body><div id="holder">\(svgSource)</div></body></html>
        """
    }
}

extension HTMLBrowserController {

    /// Loads an .svg wrapped in the viewer page. The file's folder is the base
    /// URL so images or fonts the drawing references still resolve.
    func loadSVG(fileURL: URL) -> Bool {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            // Not readable as text (or not valid UTF-8): let WebKit try the
            // raw file, which still renders most SVGs.
            load(fileURL: fileURL)
            return false
        }
        webView.loadHTMLString(SVGPage.html(svgSource: source),
                               baseURL: fileURL.deletingLastPathComponent())
        return true
    }

    /// Slider zoom, as a multiple of the fit-to-window scale.
    func svgSetScale(_ value: Double) {
        webView.evaluateJavaScript(String(format: "window.__svgSetScale && window.__svgSetScale(%.4f)", value),
                                   completionHandler: nil)
    }

    /// Page zoom for ordinary HTML pages.
    func setPageZoom(_ value: Double) {
        webView.pageZoom = CGFloat(value)
    }

    func svgZoom(_ action: String) {
        webView.evaluateJavaScript("window.__svgZoom && window.__svgZoom('\(action)')",
                                   completionHandler: nil)
    }
}
