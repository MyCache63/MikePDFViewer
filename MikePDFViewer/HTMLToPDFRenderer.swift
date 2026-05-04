import Foundation
import WebKit
import AppKit

@MainActor
final class HTMLToPDFRenderer: NSObject, WKNavigationDelegate {

    enum RenderError: Error {
        case htmlLoadFailed
        case pdfGenerationFailed
    }

    /// Render an HTML string to PDF data using WKWebView.
    /// `loadExternalImages`: when false, http(s) requests after the initial loadHTMLString are blocked.
    static func render(html: String, loadExternalImages: Bool = false) async throws -> Data {
        let renderer = HTMLToPDFRenderer(loadExternalImages: loadExternalImages)
        return try await renderer.run(html: html)
    }

    private let webView: WKWebView
    private var continuation: CheckedContinuation<Data, Error>?
    private let loadExternalImages: Bool

    private init(loadExternalImages: Bool) {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        // 8.5x11 inch page at 96 DPI = 816x1056
        let frame = NSRect(x: 0, y: 0, width: 816, height: 1056)
        self.webView = WKWebView(frame: frame, configuration: config)
        self.loadExternalImages = loadExternalImages
        super.init()
        self.webView.navigationDelegate = self
    }

    private func run(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            let config = WKPDFConfiguration()
            config.rect = nil
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    switch result {
                    case .success(let data):
                        self.continuation?.resume(returning: data)
                    case .failure(let error):
                        self.continuation?.resume(throwing: error)
                    }
                    self.continuation = nil
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Task { @MainActor in
            if navigationAction.request.url == nil || navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            if !self.loadExternalImages, let scheme = navigationAction.request.url?.scheme,
               (scheme == "http" || scheme == "https") {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
