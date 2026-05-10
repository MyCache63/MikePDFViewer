import SwiftUI
import PDFKit
import AppKit

/// Read-only embedded viewer suitable for hosting inside another app's window.
/// Designed for cases like a tab in Mission Control where the parent app owns
/// the menu bar, focus, toolbar, and notifications and just wants a SwiftUI
/// view it can hand a file URL to.
///
/// Supports the same file types as the standalone MikePDFViewer.app:
/// `.pdf`, `.md`, `.markdown`, `.docx`, `.eml`.
///
/// Does NOT include annotations, signatures, OCR, redaction, watermarks,
/// merge, or presentation mode. For those, point the user at the standalone
/// `MikePDFViewer.app` (e.g. via `NSWorkspace.shared.open(url)`).
///
/// **Embedding contract:**
/// - No `NotificationCenter.default.post` calls.
/// - No `FocusedValue` writes.
/// - No menu commands or keyboard shortcuts.
/// - No file picker prompts (the URL is the input).
/// - No window-level state (presentation mode, split view, etc.).
public struct EmbeddedDocumentView: View {
    public let fileURL: URL
    public let markdownTheme: MarkdownReaderTheme

    @State private var phase: LoadPhase = .idle

    public init(fileURL: URL, markdownTheme: MarkdownReaderTheme = .github) {
        self.fileURL = fileURL
        self.markdownTheme = markdownTheme
    }

    public var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .pdf(let doc):
                EmbeddedPDFView(document: doc)
            case .markdown(let source):
                MarkdownReaderView(source: source, baseURL: fileURL, theme: markdownTheme)
            case .error(let message):
                errorView(message)
            case .unsupported(let ext):
                errorView("Unsupported file type: .\(ext)")
            }
        }
        .onAppear { Task { await load() } }
        .onChange(of: fileURL) { _, _ in Task { await load() } }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @MainActor
    private func load() async {
        phase = .loading
        let ext = fileURL.pathExtension.lowercased()
        do {
            switch ext {
            case "pdf":
                if let doc = PDFDocument(url: fileURL) {
                    phase = .pdf(doc)
                } else {
                    phase = .error("Could not open PDF.")
                }
            case "md", "markdown":
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                phase = .markdown(source)
            case "docx":
                let (doc, _) = try await DOCXToPDFConverter.convert(url: fileURL)
                phase = .pdf(doc)
            case "eml":
                let doc = try await EMLToPDFConverter.convert(url: fileURL)
                phase = .pdf(doc)
            default:
                phase = .unsupported(ext)
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private enum LoadPhase {
        case idle
        case loading
        case pdf(PDFDocument)
        case markdown(String)
        case error(String)
        case unsupported(String)
    }
}

/// Minimal NSViewRepresentable around PDFKit's PDFView. No annotation support,
/// no print, no notification posting — just the page-rendering capability for
/// embedded read-only display.
struct EmbeddedPDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
