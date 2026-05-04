import Foundation
import AppKit
import PDFKit

@MainActor
final class MarkdownToPDFConverter {

    enum ConversionError: Error {
        case htmlConversionFailed
        case pdfRenderFailed
        case parsedDocumentInvalid
    }

    /// Convert a markdown source string into a PDFDocument.
    /// Strategy: AttributedString(markdown:) → walk runs, emit clean HTML directly →
    /// wrap with styled CSS template → render via shared HTMLToPDFRenderer.
    /// Side effect: writes the rendered PDF to TempFolderManager.tmpFolder.
    static func convert(source: String, sourceURL: URL) async throws -> (document: PDFDocument, tempPDFURL: URL) {
        let bodyHTML = generateHTML(from: source)
        let wrapped = wrapHTML(bodyHTML, title: sourceURL.lastPathComponent)
        let pdfData = try await HTMLToPDFRenderer.render(html: wrapped, loadExternalImages: false)

        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }

        let tempURL = try TempFolderManager.writeToTemp(data: pdfData, sourceURL: sourceURL)
        return (document, tempURL)
    }

    // MARK: - HTML emission

    /// Walk the parsed AttributedString and emit clean HTML with proper block-level
    /// tags (h1-h6, p, ul, ol, li, pre, code, blockquote) plus inline formatting.
    private static func generateHTML(from source: String) -> String {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard let parsed = try? AttributedString(markdown: source, options: opts) else {
            return "<pre>\(htmlEscape(source))</pre>"
        }

        var output = ""
        var openListKind: ListKind? = nil  // nil, .ordered, .unordered
        var prevBlockID: Int? = nil
        var currentBlockHTML = ""
        var currentBlockKind: BlockKind = .paragraph

        func flushBlock() {
            guard !currentBlockHTML.isEmpty else { return }
            output += renderBlock(kind: currentBlockKind, content: currentBlockHTML)
            currentBlockHTML = ""
        }

        func closeListIfNeeded(except newKind: ListKind? = nil) {
            if let kind = openListKind, kind != newKind {
                output += (kind == .ordered) ? "</ol>" : "</ul>"
                openListKind = nil
            }
        }

        for run in parsed.runs {
            let intent = run.presentationIntent
            let id = intent?.components.first?.identity

            // Block boundary — flush prior block.
            if id != prevBlockID {
                flushBlock()
            }

            // Determine new block kind from intent.
            let blockKind = classifyBlock(intent: intent)
            currentBlockKind = blockKind

            // Handle list opening / closing tags.
            switch blockKind {
            case .listItemOrdered:
                if openListKind != .ordered {
                    closeListIfNeeded(except: .ordered)
                    output += "<ol>"
                    openListKind = .ordered
                }
            case .listItemUnordered:
                if openListKind != .unordered {
                    closeListIfNeeded(except: .unordered)
                    output += "<ul>"
                    openListKind = .unordered
                }
            default:
                closeListIfNeeded()
            }

            // Append this run's inline-formatted text to the current block.
            let runText = String(parsed[run.range].characters)
            currentBlockHTML += renderInline(text: runText, run: run)

            prevBlockID = id
        }

        // Flush remaining content.
        flushBlock()
        closeListIfNeeded()

        return output
    }

    private enum ListKind { case ordered, unordered }

    private enum BlockKind {
        case paragraph
        case header(Int)
        case codeBlock
        case blockQuote
        case listItemOrdered
        case listItemUnordered
        case thematicBreak
    }

    private static func classifyBlock(intent: PresentationIntent?) -> BlockKind {
        guard let intent = intent else { return .paragraph }

        var isOrderedList = false
        var isUnorderedList = false
        var isListItem = false

        for component in intent.components {
            switch component.kind {
            case .header(level: let lvl):
                return .header(lvl)
            case .codeBlock:
                return .codeBlock
            case .blockQuote:
                return .blockQuote
            case .thematicBreak:
                return .thematicBreak
            case .orderedList:
                isOrderedList = true
            case .unorderedList:
                isUnorderedList = true
            case .listItem:
                isListItem = true
            default:
                break
            }
        }

        if isListItem && isOrderedList { return .listItemOrdered }
        if isListItem && isUnorderedList { return .listItemUnordered }
        return .paragraph
    }

    private static func renderBlock(kind: BlockKind, content: String) -> String {
        switch kind {
        case .paragraph:
            return "<p>\(content)</p>"
        case .header(let level):
            let lvl = max(1, min(level, 6))
            return "<h\(lvl)>\(content)</h\(lvl)>"
        case .codeBlock:
            return "<pre><code>\(content)</code></pre>"
        case .blockQuote:
            return "<blockquote>\(content)</blockquote>"
        case .listItemOrdered, .listItemUnordered:
            return "<li>\(content)</li>"
        case .thematicBreak:
            return "<hr>"
        }
    }

    private static func renderInline(text: String, run: AttributedString.Runs.Run) -> String {
        var html = htmlEscape(text)
        let inline = run.inlinePresentationIntent ?? []

        if inline.contains(.code) {
            html = "<code>\(html)</code>"
        }
        if inline.contains(.stronglyEmphasized) {
            html = "<strong>\(html)</strong>"
        }
        if inline.contains(.emphasized) {
            html = "<em>\(html)</em>"
        }
        if inline.contains(.strikethrough) {
            html = "<s>\(html)</s>"
        }
        if let link = run.link {
            html = "<a href=\"\(htmlEscape(link.absoluteString))\">\(html)</a>"
        }
        return html
    }

    private static func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - HTML wrapper

    private static func wrapHTML(_ body: String, title: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(htmlEscape(title))</title>
            <style>
                @page { margin: 0.5in; }
                body {
                    font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
                    font-size: 12pt;
                    line-height: 1.55;
                    color: #1a1a1a;
                    margin: 0;
                    padding: 0;
                }
                h1 { font-size: 22pt; margin-top: 0.4em; margin-bottom: 0.5em; color: #000; border-bottom: 1px solid #ddd; padding-bottom: 0.2em; }
                h2 { font-size: 18pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #000; }
                h3 { font-size: 15pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #222; }
                h4, h5, h6 { font-size: 12pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #333; }
                p { margin: 0.5em 0; }
                code {
                    font-family: "SF Mono", Menlo, Consolas, monospace;
                    font-size: 11pt;
                    background: #f4f4f4;
                    padding: 1px 4px;
                    border-radius: 3px;
                }
                pre {
                    font-family: "SF Mono", Menlo, Consolas, monospace;
                    font-size: 10.5pt;
                    background: #f4f4f4;
                    padding: 12px;
                    border-radius: 4px;
                    overflow-x: auto;
                    line-height: 1.4;
                    white-space: pre-wrap;
                }
                pre code { background: transparent; padding: 0; font-size: inherit; }
                blockquote {
                    border-left: 3px solid #888;
                    padding-left: 12px;
                    margin: 0.6em 0;
                    color: #555;
                    font-style: italic;
                }
                ul, ol { margin: 0.5em 0 0.5em 1.4em; padding-left: 0.5em; }
                li { margin: 0.2em 0; }
                table {
                    border-collapse: collapse;
                    margin: 0.6em 0;
                    max-width: 100%;
                }
                th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: left; }
                th { background: #f4f4f4; font-weight: 600; }
                a { color: #0a5cc4; text-decoration: underline; }
                img { max-width: 100%; height: auto; }
                hr { border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }
            </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
