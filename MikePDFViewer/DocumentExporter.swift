import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Which output the user asked for from File > Export or the toolbar Export menu.
enum ExportFormat: String {
    case pdf, docx, png

    var menuTitle: String {
        switch self {
        case .pdf:  return "Export as PDF…"
        case .docx: return "Export as Word (.docx)…"
        case .png:  return "Export as PNG…"
        }
    }
}

/// Small helpers shared by the export paths in ContentView. The per-mode
/// logic (which viewer is active, how to get a PDF or attributed text from
/// it) stays in ContentView because that is where the mode state lives.
@MainActor
enum DocumentExporter {

    /// Standard save panel starting next to the source file.
    static func chooseDestination(suggestedName: String,
                                  type: UTType,
                                  near sourceURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let dir = sourceURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Word file built by AppKit's Office Open XML writer. Fonts, bold,
    /// italics, headings and lists in the attributed string carry across.
    static func writeDOCX(_ attributed: NSAttributedString, to url: URL) throws {
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: url, options: .atomic)
    }

    /// Text of every page of a PDF, page breaks preserved as blank lines.
    /// Scanned pages with no text layer contribute nothing (run Make
    /// Searchable first for those).
    static func attributedString(from document: PDFDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.attributedString, text.length > 0 {
                result.append(text)
            }
            if index < document.pageCount - 1 {
                result.append(NSAttributedString(string: "\n\n"))
            }
        }
        return result
    }

    /// A delimited file as an HTML table, for print and PDF export. Repeating
    /// the header on every printed page is what makes a long table readable.
    static func html(forTable columns: [String], rows: [[String]], title: String) -> String {
        func escape(_ text: String) -> String {
            var out = text
            for (from, to) in [("&", "&amp;"), ("<", "&lt;"), (">", "&gt;")] {
                out = out.replacingOccurrences(of: from, with: to)
            }
            return out
        }
        let head = columns.map { "<th>\(escape($0))</th>" }.joined()
        let body = rows.map { row in
            "<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>"
        }.joined()
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 9pt; margin: 0; }
        h1 { font-size: 12pt; margin: 0 0 8pt 0; }
        table { border-collapse: collapse; width: 100%; }
        thead { display: table-header-group; }
        tr { page-break-inside: avoid; }
        th, td { border: 0.5pt solid #999; padding: 3pt 5pt; text-align: left;
                 vertical-align: top; word-break: break-word; }
        th { background: #eee; font-weight: 600; }
        </style></head><body>
        <h1>\(escape(title))</h1>
        <table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>
        </body></html>
        """
    }

    /// Plain text (txt/log/json) wrapped as preformatted HTML so it can go
    /// through the paginated renderer and become a real multi-page PDF.
    static func html(forPlainText text: String, font: NSFont) -> String {
        var escaped = text
        for (from, to) in [("&", "&amp;"), ("<", "&lt;"), (">", "&gt;")] {
            escaped = escaped.replacingOccurrences(of: from, with: to)
        }
        let family = font.familyName ?? "Menlo"
        return """
        <html><head><meta charset="utf-8"><style>
        body { margin: 0; }
        pre { font-family: '\(family)', Menlo, monospace; font-size: \(Int(font.pointSize))pt;
              white-space: pre-wrap; word-wrap: break-word; margin: 0; }
        </style></head><body><pre>\(escaped)</pre></body></html>
        """
    }
}
