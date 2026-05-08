import Foundation

/// Converts markdown source to clean HTML by walking AttributedString.runs and
/// emitting proper block-level tags (h1–h6, p, ul, ol, li, pre, code, blockquote).
/// Used by both MarkdownReaderView (WKWebView display) and MarkdownToPDFConverter
/// (Render-as-PDF), so theme-aware PDF export is automatic.
enum MarkdownToHTML {

    /// A single TOC entry, captured while emitting headings.
    struct TOCEntry: Equatable {
        let level: Int
        let text: String
        let slug: String
    }

    /// Render markdown body HTML and a parallel TOC list.
    /// The result is body content only (no `<html>`/`<head>`); callers wrap it.
    static func render(_ source: String) -> (html: String, toc: [TOCEntry]) {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard let parsed = try? AttributedString(markdown: source, options: opts) else {
            return ("<pre>\(htmlEscape(source))</pre>", [])
        }

        var output = ""
        var toc: [TOCEntry] = []
        var openListKind: ListKind? = nil
        var prevBlockID: Int? = nil
        var currentBlockHTML = ""
        var currentBlockKind: BlockKind = .paragraph
        var currentBlockText = ""

        func flushBlock() {
            guard !currentBlockHTML.isEmpty || isStandaloneBlock(currentBlockKind) else { return }
            output += renderBlock(kind: currentBlockKind, content: currentBlockHTML, plainText: currentBlockText, toc: &toc)
            currentBlockHTML = ""
            currentBlockText = ""
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

            if id != prevBlockID {
                flushBlock()
            }

            currentBlockKind = classifyBlock(intent: intent)

            switch currentBlockKind {
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

            let runText = String(parsed[run.range].characters)
            currentBlockText += runText
            currentBlockHTML += renderInline(text: runText, run: run)

            prevBlockID = id
        }

        flushBlock()
        closeListIfNeeded()

        return (output, toc)
    }

    /// Convenience wrapper for callers who only need the HTML.
    static func renderHTML(_ source: String) -> String {
        return render(source).html
    }

    // MARK: - Block / list classification

    enum ListKind { case ordered, unordered }

    enum BlockKind {
        case paragraph
        case header(Int)
        case codeBlock
        case blockQuote
        case listItemOrdered
        case listItemUnordered
        case thematicBreak
    }

    private static func isStandaloneBlock(_ kind: BlockKind) -> Bool {
        if case .thematicBreak = kind { return true }
        return false
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

    // MARK: - Block emission

    private static func renderBlock(kind: BlockKind,
                                    content: String,
                                    plainText: String,
                                    toc: inout [TOCEntry]) -> String {
        switch kind {
        case .paragraph:
            return "<p>\(content)</p>"
        case .header(let level):
            let lvl = max(1, min(level, 6))
            let slug = MarkdownDocument.slugify(plainText)
            toc.append(TOCEntry(level: lvl, text: plainText, slug: slug))
            return "<h\(lvl) id=\"\(htmlEscape(slug))\">\(content)</h\(lvl)>"
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

    // MARK: - Inline emission

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

    // MARK: - Utilities

    static func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
