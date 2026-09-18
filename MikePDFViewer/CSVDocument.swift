import SwiftUI
import AppKit

/// A parsed delimited file. Handles the awkward parts of real CSV: quoted
/// fields, commas and newlines inside quotes, and doubled quotes as an escape.
struct CSVDocument: Sendable {
    let columns: [String]
    let rows: [[String]]
    let delimiterName: String

    var rowCount: Int { rows.count }
    var columnCount: Int { columns.count }

    var summary: String {
        "\(rowCount) row\(rowCount == 1 ? "" : "s"), \(columnCount) column\(columnCount == 1 ? "" : "s")"
    }

    /// Tab for .tsv. For .csv, whichever of comma or semicolon appears more on
    /// the first line, because exports from European tools use semicolons.
    static func detectDelimiter(text: String, fileExtension: String) -> Character {
        if ["tsv", "tab"].contains(fileExtension.lowercased()) { return "\t" }
        let firstLine = text.split(whereSeparator: \.isNewline).first ?? ""
        let commas = firstLine.filter { $0 == "," }.count
        let semicolons = firstLine.filter { $0 == ";" }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        if tabs > commas && tabs > semicolons { return "\t" }
        return semicolons > commas ? ";" : ","
    }

    static func parse(text: String, delimiter: Character, firstRowIsHeader: Bool) -> CSVDocument {
        var records = splitRecords(text: text, delimiter: delimiter)
        guard !records.isEmpty else {
            return CSVDocument(columns: [], rows: [], delimiterName: name(for: delimiter))
        }
        let width = records.map(\.count).max() ?? 0
        var columns: [String]
        if firstRowIsHeader {
            let header = records.removeFirst()
            columns = (0..<width).map { index in
                let raw = index < header.count ? header[index].trimmingCharacters(in: .whitespaces) : ""
                return raw.isEmpty ? "Column \(index + 1)" : raw
            }
        } else {
            columns = (0..<width).map { "Column \($0 + 1)" }
        }
        // Pad short rows so every row lines up with the header.
        let padded = records.map { row -> [String] in
            row.count == width ? row : row + Array(repeating: "", count: width - row.count)
        }
        return CSVDocument(columns: columns, rows: padded, delimiterName: name(for: delimiter))
    }

    private static func name(for delimiter: Character) -> String {
        switch delimiter {
        case "\t": return "tab"
        case ";":  return "semicolon"
        default:   return "comma"
        }
    }

    private static func splitRecords(text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        func endField() {
            record.append(field)
            field = ""
        }
        func endRecord() {
            endField()
            records.append(record)
            record = []
        }

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    // A doubled quote inside quotes means one literal quote.
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(character)
                index += 1
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case delimiter:
                endField()
            case "\r":
                if index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                endRecord()
            case "\n":
                endRecord()
            default:
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        // Drop a trailing blank line.
        return records.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

/// Read-only spreadsheet-style table. NSTableView only builds the rows on
/// screen, so a file with tens of thousands of rows still opens instantly.
struct CSVTableView: NSViewRepresentable {
    let document: CSVDocument
    var fontScale: Double = 1.0

    func makeCoordinator() -> Coordinator { Coordinator(document: document, fontScale: fontScale) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.allowsMultipleSelection = true
        table.rowSizeStyle = .small
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.rebuildColumns(in: table)

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let table = scrollView.documentView as? NSTableView else { return }
        let wanted = Coordinator.signature(for: document, fontScale: fontScale)
        if context.coordinator.signature != wanted {
            context.coordinator.document = document
            context.coordinator.fontScale = fontScale
            context.coordinator.rebuildColumns(in: table)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var document: CSVDocument
        var fontScale: Double
        private(set) var signature: String

        init(document: CSVDocument, fontScale: Double) {
            self.document = document
            self.fontScale = fontScale
            self.signature = Coordinator.signature(for: document, fontScale: fontScale)
        }

        static func signature(for document: CSVDocument, fontScale: Double) -> String {
            "\(document.columns.joined(separator: "\u{1}"))|\(document.rowCount)|\(Int(fontScale * 100))"
        }

        private var cellFontSize: CGFloat { max(7, 12 * CGFloat(fontScale)) }

        func rebuildColumns(in table: NSTableView) {
            signature = Coordinator.signature(for: document, fontScale: fontScale)
            table.rowSizeStyle = .custom
            table.rowHeight = max(14, 17 * CGFloat(fontScale))
            for column in table.tableColumns { table.removeTableColumn(column) }

            let numbers = NSTableColumn(identifier: .init("rowNumber"))
            numbers.title = "#"
            numbers.width = 48 * max(0.6, CGFloat(fontScale))
            numbers.minWidth = 36
            table.addTableColumn(numbers)

            for (index, name) in document.columns.enumerated() {
                let column = NSTableColumn(identifier: .init("col\(index)"))
                column.title = name
                column.width = estimatedWidth(forColumn: index, title: name)
                column.minWidth = 48
                table.addTableColumn(column)
            }
            table.reloadData()
        }

        /// Sample the first rows so columns open at a sensible width instead of
        /// every column being identical.
        private func estimatedWidth(forColumn index: Int, title: String) -> CGFloat {
            let font = NSFont.systemFont(ofSize: cellFontSize)
            var widest = (title as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: cellFontSize)]).width
            for row in document.rows.prefix(100) {
                guard index < row.count else { continue }
                let width = (row[index] as NSString).size(withAttributes: [.font: font]).width
                widest = max(widest, width)
            }
            return min(max(widest + 24, 60), 380 * max(1, CGFloat(fontScale)))
        }

        func numberOfRows(in tableView: NSTableView) -> Int { document.rowCount }

        func tableView(_ tableView: NSTableView,
                       viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let identifier = tableColumn.identifier
            let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                field = reused
            } else {
                field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.lineBreakMode = .byTruncatingTail
                field.font = .systemFont(ofSize: cellFontSize)
            }

            field.font = .systemFont(ofSize: cellFontSize)
            if identifier.rawValue == "rowNumber" {
                field.stringValue = "\(row + 1)"
                field.textColor = .tertiaryLabelColor
                field.alignment = .right
            } else {
                let index = Int(identifier.rawValue.dropFirst(3)) ?? 0
                let value = index < document.rows[row].count ? document.rows[row][index] : ""
                field.stringValue = value
                field.textColor = .labelColor
                field.alignment = .left
            }
            return field
        }
    }
}
