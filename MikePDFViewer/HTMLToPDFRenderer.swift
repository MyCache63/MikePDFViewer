import Foundation
import WebKit
import AppKit

@MainActor
public final class HTMLToPDFRenderer: NSObject, WKNavigationDelegate {

    public enum RenderError: Error {
        case htmlLoadFailed
        case pdfGenerationFailed
    }

    /// Render an HTML string to PDF data using WKWebView.
    /// `loadExternalImages`: when false, http(s) requests after the initial loadHTMLString are blocked.
    public static func render(html: String, loadExternalImages: Bool = false) async throws -> Data {
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

    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    nonisolated public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    nonisolated public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    nonisolated public func webView(_ webView: WKWebView,
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

// MARK: - Paginated rendering (for print)

/// Renders HTML into a MULTI-PAGE letter-size PDF via WKWebView's print
/// operation. `HTMLToPDFRenderer.render` above uses createPDF, which returns
/// the whole document as ONE tall page: fine on screen, but the print dialog
/// then scales it onto a single unreadable sheet. Technique per
/// https://developer.apple.com/forums/thread/705138 (print-to-file requires
/// runModal, not run; no panel is actually shown).
@MainActor
public final class PaginatedHTMLToPDF: NSObject, WKNavigationDelegate {

    public enum RenderError: Error {
        case pdfGenerationFailed
    }

    /// `marginInches` applies to all four sides of US Letter paper.
    public static func render(html: String, marginInches: Double = 0.5) async throws -> Data {
        let renderer = PaginatedHTMLToPDF(marginInches: marginInches)
        return try await renderer.run(html: html)
    }

    private let webView: WKWebView
    private let window: NSWindow
    private let marginInches: Double
    private var continuation: CheckedContinuation<Data, Error>?
    private var saveURL: URL?

    private init(marginInches: Double) {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        let frame = NSRect(x: 0, y: 0, width: 816, height: 1056)
        self.webView = WKWebView(frame: frame, configuration: config)
        // The print operation needs a window to attach its modal session to;
        // this one is never ordered front, so nothing appears on screen.
        self.window = NSWindow(contentRect: frame, styleMask: .borderless,
                               backing: .buffered, defer: true)
        self.marginInches = marginInches
        super.init()
        window.contentView?.addSubview(webView)
        webView.navigationDelegate = self
    }

    private func run(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.startPrintToPDF()
        }
    }

    private func startPrintToPDF() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdprint-\(UUID().uuidString).pdf")
        saveURL = url

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter in points
        let margin = CGFloat(marginInches * 72.0)
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                    contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ printOperation: NSPrintOperation,
                                            success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        guard success, let url = saveURL, let data = try? Data(contentsOf: url) else {
            continuation?.resume(throwing: RenderError.pdfGenerationFailed)
            continuation = nil
            return
        }
        try? FileManager.default.removeItem(at: url)
        continuation?.resume(returning: data)
        continuation = nil
    }

    nonisolated public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }

    nonisolated public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
