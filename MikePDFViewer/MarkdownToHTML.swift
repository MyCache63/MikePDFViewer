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
        var table: TableAccumulator? = nil

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

        func flushTable() {
            if let t = table {
                output += t.render()
                table = nil
            }
        }

        for run in parsed.runs {
            let intent = run.presentationIntent
            let runText = String(parsed[run.range].characters)

            // GFM tables: each cell is its own block in AttributedString land
            // (innermost component is .tableCell). Route them into a
            // TableAccumulator so we emit one <table>...</table> instead of
            // many <p>cell</p> paragraphs.
            if let intent = intent, let info = tableInfo(from: intent) {
                if table == nil {
                    flushBlock()
                    closeListIfNeeded()
                }
                if table?.tableID != info.tableID {
                    flushTable()
                    table = TableAccumulator(tableID: info.tableID, columns: info.columns)
                }
                let html = renderInline(text: runText, run: run)
                table!.add(rowID: info.rowID,
                           isHeader: info.isHeader,
                           cellID: info.cellID,
                           cellIndex: info.cellIndex,
                           html: html)
                prevBlockID = nil  // table runs sit outside normal block tracking
                continue
            }

            // Non-table run — flush any pending table first.
            flushTable()

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

            currentBlockText += runText
            currentBlockHTML += renderInline(text: runText, run: run)

            prevBlockID = id
        }

        flushBlock()
        flushTable()
        closeListIfNeeded()

        return (output, toc)
    }

    // MARK: - Table support

    /// Pulled out of a run's PresentationIntent: the table / row / cell ids
    /// plus whether the row is a header row and the cell's column index.
    /// Returns nil if the intent isn't part of a table.
    private struct TableInfo {
        let tableID: Int
        let columns: [PresentationIntent.TableColumn]
        let rowID: Int
        let isHeader: Bool
        let cellID: Int
        let cellIndex: Int
    }

    private static func tableInfo(from intent: PresentationIntent) -> TableInfo? {
        var tableID: Int? = nil
        var columns: [PresentationIntent.TableColumn] = []
        var rowID: Int? = nil
        var isHeader = false
        var cellID: Int? = nil
        var cellIndex: Int? = nil

        for component in intent.components {
            switch component.kind {
            case .table(let cols):
                tableID = component.identity
                columns = cols
            case .tableHeaderRow:
                rowID = component.identity
                isHeader = true
            case .tableRow:
                rowID = component.identity
                isHeader = false
            case .tableCell(let idx):
                cellID = component.identity
                cellIndex = idx
            default:
                break
            }
        }

        guard let tID = tableID, let rID = rowID, let cID = cellID, let cIdx = cellIndex else {
            return nil
        }
        return TableInfo(tableID: tID, columns: columns, rowID: rID, isHeader: isHeader, cellID: cID, cellIndex: cIdx)
    }

    /// Streams cell HTML into rows and rows into a single table, then emits
    /// `<table><thead>...<tbody>...</table>`. Handles continuation runs (e.g.
    /// a cell with bold inline produces multiple runs sharing the same cell ID)
    /// by appending into the last cell when the cell ID hasn't changed.
    private final class TableAccumulator {
        let tableID: Int
        let columns: [PresentationIntent.TableColumn]

        private var rows: [Row] = []
        private var currentRow: Row? = nil
        private var currentRowID: Int? = nil
        private var currentCellID: Int? = nil

        struct Row {
            var isHeader: Bool
            var cells: [Cell] = []
        }
        struct Cell {
            var columnIndex: Int
            var html: String
        }

        init(tableID: Int, columns: [PresentationIntent.TableColumn]) {
            self.tableID = tableID
            self.columns = columns
        }

        func add(rowID: Int, isHeader: Bool, cellID: Int, cellIndex: Int, html: String) {
            if currentRowID != rowID {
                // New row — push the prior one and start fresh.
                if let row = currentRow {
                    rows.append(row)
                }
                currentRow = Row(isHeader: isHeader)
                currentRowID = rowID
                currentCellID = nil
            }
            if currentCellID != cellID {
                currentRow?.cells.append(Cell(columnIndex: cellIndex, html: html))
                currentCellID = cellID
            } else if let lastIdx = currentRow?.cells.indices.last {
                // Continuation of the same cell — append HTML.
                currentRow?.cells[lastIdx].html += html
            }
        }

        func render() -> String {
            if let row = currentRow {
                rows.append(row)
            }
            let headers = rows.filter { $0.isHeader }
            let body = rows.filter { !$0.isHeader }
            var html = "<table>"
            if !headers.isEmpty {
                html += "<thead>"
                for row in headers { html += renderRow(row, asHeader: true) }
                html += "</thead>"
            }
            if !body.isEmpty {
                html += "<tbody>"
                for row in body { html += renderRow(row, asHeader: false) }
                html += "</tbody>"
            }
            html += "</table>"
            return html
        }

        private func renderRow(_ row: Row, asHeader: Bool) -> String {
            let tag = asHeader ? "th" : "td"

            // Apple's AttributedString markdown parser emits NO run for an empty
            // cell, so empty cells never reach this accumulator — they're simply
            // absent from `row.cells`. If we rendered cells in sequence, a row
            // with an empty cell (e.g. a header whose top-left corner is blank)
            // would come out one column short and every cell after the gap would
            // shift. So place each cell at its true columnIndex and fill any
            // missing column with an empty cell to keep every row aligned.
            let maxSeen = (row.cells.map { $0.columnIndex }.max() ?? -1) + 1
            let colCount = max(columns.count, maxSeen)
            guard colCount > 0 else { return "<tr></tr>" }

            var cellHTML = [String](repeating: "", count: colCount)
            for cell in row.cells where cell.columnIndex >= 0 && cell.columnIndex < colCount {
                cellHTML[cell.columnIndex] = cell.html
            }

            var html = "<tr>"
            for idx in 0..<colCount {
                let align = idx < columns.count ? cssAlignment(columns[idx].alignment) : ""
                let style = align.isEmpty ? "" : " style=\"text-align:\(align)\""
                html += "<\(tag)\(style)>\(cellHTML[idx])</\(tag)>"
            }
            html += "</tr>"
            return html
        }

        private func cssAlignment(_ a: PresentationIntent.TableColumn.Alignment) -> String {
            switch a {
            case .left: return "left"
            case .center: return "center"
            case .right: return "right"
            @unknown default: return ""
            }
        }
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
