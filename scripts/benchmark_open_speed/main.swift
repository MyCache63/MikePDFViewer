import Foundation
import AppKit
import WebKit

// Benchmark of the MikePDFViewer markdown open path, stage by stage.
// Usage: ./benchmark <file.md> [runs]

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: benchmark <file.md> [runs]"); exit(1) }
let url = URL(fileURLWithPath: args[1])
let runs = args.count >= 3 ? Int(args[2]) ?? 3 : 3

func timeMS(_ block: () -> Void) -> Double {
    let t0 = CFAbsoluteTimeGetCurrent()
    block()
    return (CFAbsoluteTimeGetCurrent() - t0) * 1000
}

func report(_ label: String, _ values: [Double]) {
    let avg = values.reduce(0, +) / Double(values.count)
    let list = values.map { String(format: "%.0f", $0) }.joined(separator: "/")
    print(String(format: "%-42@ avg %6.1f ms  (runs: %@)", label as NSString, avg, list as NSString))
}

let sizeKB = (try? Data(contentsOf: url).count ?? 0).map { $0 / 1024 } ?? 0
print("=== \(url.lastPathComponent) (\(sizeKB) KB), \(runs) runs ===")

var parseT: [Double] = [], styledT: [Double] = [], htmlT: [Double] = []
var statsT: [Double] = [], themeT: [Double] = [], bookmarkT: [Double] = []

var doc: MarkdownDocument!
var html = ""
for _ in 0..<runs {
    parseT.append(timeMS { doc = try! MarkdownDocument(url: url) })
    styledT.append(timeMS { _ = doc.styledAttributedStringWithAnchors() })
    htmlT.append(timeMS { html = MarkdownToHTML.render(doc.source).html })
    statsT.append(timeMS { _ = ReadingStats(source: doc.source) })
    themeT.append(timeMS {
        _ = MarkdownReaderThemeBundle.html(body: html, title: url.lastPathComponent,
                                           theme: .github, typography: .default, focusMode: false)
    })
    bookmarkT.append(timeMS {
        _ = try? url.bookmarkData(options: .withSecurityScope,
                                  includingResourceValuesForKeys: nil, relativeTo: nil)
    })
}
report("MarkdownDocument(url:) read+parse", parseT)
report("styledAttributedStringWithAnchors (Quick)", styledT)
report("MarkdownToHTML.render", htmlT)
report("ReadingStats", statsT)
report("ThemeBundle.html", themeT)
report("bookmarkData(.withSecurityScope)", bookmarkT)

// WKWebView render: time loadHTMLString -> didFinish, cold then warm.
let themed = MarkdownReaderThemeBundle.html(body: html, title: url.lastPathComponent,
                                            theme: .github, typography: .default, focusMode: false)

final class LoadTimer: NSObject, WKNavigationDelegate {
    var start: CFAbsoluteTime = 0
    var done: ((Double) -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done?((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

let app = NSApplication.shared
var webT: [Double] = []
var webViews: [WKWebView] = []
var timers: [LoadTimer] = []
var pass = 0

func nextPass() {
    if pass >= runs + 1 {
        report("WKWebView load->didFinish COLD (first)", [webT[0]])
        report("WKWebView load->didFinish warm", Array(webT.dropFirst()))
        exit(0)
    }
    // A NEW webview each pass mirrors the app (one per open/window).
    let config = WKWebViewConfiguration()
    let prefs = WKWebpagePreferences()
    prefs.allowsContentJavaScript = true
    config.defaultWebpagePreferences = prefs
    let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 800), configuration: config)
    let timer = LoadTimer()
    wv.navigationDelegate = timer
    webViews.append(wv)   // keep alive, simulates several open windows
    timers.append(timer)
    timer.done = { ms in
        webT.append(ms)
        pass += 1
        DispatchQueue.main.async { nextPass() }
    }
    timer.start = CFAbsoluteTimeGetCurrent()
    wv.loadHTMLString(themed, baseURL: nil)
}

DispatchQueue.main.async { nextPass() }
app.run()
