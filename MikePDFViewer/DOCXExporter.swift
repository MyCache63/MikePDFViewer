import Foundation

struct DOCXExporter {

    static func export(pages: [OCRPageResult]) throws -> Data {
        let coverPages = pages.filter { $0.isCoverPage }
        let contentPages = pages.filter { !$0.isCoverPage }

        // Collect all footnotes across pages for the footnotes.xml file
        var allFootnotes: [String] = []
        for page in pages {
            allFootnotes.append(contentsOf: extractFootnotes(from: page.text))
        }

        let documentXML = buildDocumentXML(
            coverPages: coverPages,
            contentPages: contentPages,
            footnoteCount: allFootnotes.count
        )
        let footnotesXML = buildFootnotesXML(footnotes: allFootnotes)
        let stylesXML = buildStylesXML()
        let contentTypesXML = buildContentTypesXML(hasFootnotes: !allFootnotes.isEmpty)
        let relsXML = buildRelsXML()
        let documentRelsXML = buildDocumentRelsXML(hasFootnotes: !allFootnotes.isEmpty)

        var zip = ZIPWriter()
        zip.addEntry(name: "[Content_Types].xml", data: contentTypesXML.data(using: .utf8)!)
        zip.addEntry(name: "_rels/.rels", data: relsXML.data(using: .utf8)!)
        zip.addEntry(name: "word/document.xml", data: documentXML.data(using: .utf8)!)
        zip.addEntry(name: "word/styles.xml", data: stylesXML.data(using: .utf8)!)
        zip.addEntry(name: "word/_rels/document.xml.rels", data: documentRelsXML.data(using: .utf8)!)
        if !allFootnotes.isEmpty {
            zip.addEntry(name: "word/footnotes.xml", data: footnotesXML.data(using: .utf8)!)
        }

        return zip.write()
    }

    // MARK: - Footnote Extraction

    private static func extractFootnotes(from text: String) -> [String] {
        var footnotes: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Footnote]:") {
                let note = trimmed.replacingOccurrences(of: "[Footnote]:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !note.isEmpty {
                    footnotes.append(note)
                }
            }
        }
        return footnotes
    }

    private static func stripFootnoteLines(from text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[Footnote]:") }
            .joined(separator: "\n")
    }

    // MARK: - Document XML

    private static func buildDocumentXML(
        coverPages: [OCRPageResult],
        contentPages: [OCRPageResult],
        footnoteCount: Int
    ) -> String {
        var body = ""
        // Track which footnote we're on (IDs start at 1; 0 is reserved for separator)
        var footnoteIndex = 1

        // Cover page content (single column, centered)
        for page in coverPages {
            let cleanText = stripFootnoteLines(from: page.text)
            let pageFootnotes = extractFootnotes(from: page.text)
            let blocks = parseMarkdown(cleanText)
            for block in blocks {
                switch block {
                case .heading(let text):
                    body += paragraph(text: text, style: "Title", alignment: "center", bold: true, fontSize: 32)
                case .body(let text):
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    // Check if this paragraph should get a footnote reference
                    let fnRef = findFootnoteAnchor(in: text, footnotes: pageFootnotes, startIndex: footnoteIndex)
                    if let ref = fnRef {
                        body += paragraphWithFootnote(text: text, footnoteId: ref.id, alignment: "center", fontSize: 24)
                        footnoteIndex = ref.nextIndex
                    } else {
                        body += paragraph(text: text, alignment: "center", fontSize: 24)
                    }
                case .figure(let text):
                    body += paragraph(text: text, alignment: "center", italic: true, fontSize: 20)
                }
            }
            footnoteIndex += pageFootnotes.count - max(0, footnoteIndex - footnoteIndex) // advance past any unused
        }

        // Section break: end single-column, start two-column
        if !coverPages.isEmpty && !contentPages.isEmpty {
            body += """
            <w:p><w:pPr><w:sectPr>
                <w:pgSz w:w="12240" w:h="15840"/>
                <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>
                <w:cols w:num="1" w:space="720"/>
            </w:sectPr></w:pPr></w:p>
            """
        }

        // Content pages (two column)
        for page in contentPages {
            let cleanText = stripFootnoteLines(from: page.text)
            let pageFootnotes = extractFootnotes(from: page.text)
            let blocks = parseMarkdown(cleanText)
            var pageFootnoteOffset = 0

            for block in blocks {
                switch block {
                case .heading(let text):
                    body += paragraph(text: text, style: "Heading2", bold: true, fontSize: 22)
                case .body(let text):
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    // Insert footnote ref if this paragraph contains the anchor marker
                    if pageFootnoteOffset < pageFootnotes.count {
                        let fn = pageFootnotes[pageFootnoteOffset]
                        if textContainsAnchor(text, for: fn) {
                            body += paragraphWithFootnote(text: text, footnoteId: footnoteIndex, fontSize: 20)
                            footnoteIndex += 1
                            pageFootnoteOffset += 1
                            continue
                        }
                    }
                    body += paragraph(text: text, fontSize: 20)
                case .figure(let text):
                    body += paragraph(text: text, italic: true, fontSize: 20)
                }
            }
            // If footnotes weren't matched to a paragraph, attach them to the last paragraph
            while pageFootnoteOffset < pageFootnotes.count {
                footnoteIndex += 1
                pageFootnoteOffset += 1
            }
        }

        // Final section properties
        let finalSection: String
        if !contentPages.isEmpty {
            finalSection = """
            <w:sectPr>
                <w:pgSz w:w="12240" w:h="15840"/>
                <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>
                <w:cols w:num="2" w:space="720"/>
            </w:sectPr>
            """
        } else {
            finalSection = """
            <w:sectPr>
                <w:pgSz w:w="12240" w:h="15840"/>
                <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>
                <w:cols w:num="1" w:space="720"/>
            </w:sectPr>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
                    xmlns:mo="http://schemas.microsoft.com/office/mac/office/2008/main"
                    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                    xmlns:mv="urn:schemas-microsoft-com:mac:vml"
                    xmlns:o="urn:schemas-microsoft-com:office:office"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
                    xmlns:v="urn:schemas-microsoft-com:vml"
                    xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:w10="urn:schemas-microsoft-com:office:word"
                    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
                    xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
                    xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
                    xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
                    xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
                    mc:Ignorable="w14 wp14">
            <w:body>
                \(body)
                \(finalSection)
            </w:body>
        </w:document>
        """
    }

    // MARK: - Footnote Anchor Matching

    private struct FootnoteRef {
        let id: Int
        let nextIndex: Int
    }

    private static func findFootnoteAnchor(in text: String, footnotes: [String], startIndex: Int) -> FootnoteRef? {
        for (i, fn) in footnotes.enumerated() {
            if textContainsAnchor(text, for: fn) {
                return FootnoteRef(id: startIndex + i, nextIndex: startIndex + i + 1)
            }
        }
        return nil
    }

    private static func textContainsAnchor(_ text: String, for footnote: String) -> Bool {
        // Match footnote markers: *, †, ‡, or the first word of the footnote
        // For "*Member AIAA" → look for "*" or "III*" in the text
        if footnote.hasPrefix("*") {
            return text.contains("*")
        }
        if footnote.hasPrefix("†") {
            return text.contains("†")
        }
        if footnote.hasPrefix("‡") {
            return text.contains("‡")
        }
        // For numbered footnotes like "1. Some note" → look for superscript-style ref
        let firstWord = footnote.components(separatedBy: .whitespaces).first ?? ""
        if let num = Int(firstWord.trimmingCharacters(in: CharacterSet(charactersIn: ".)"))) {
            return text.contains("[\(num)]")
        }
        return false
    }

    // MARK: - Footnotes XML

    private static func buildFootnotesXML(footnotes: [String]) -> String {
        var entries = ""

        // Footnote 0: the separator (required by OOXML spec)
        entries += """
        <w:footnote w:type="separator" w:id="-1">
            <w:p><w:r><w:separator/></w:r></w:p>
        </w:footnote>
        <w:footnote w:type="continuationSeparator" w:id="0">
            <w:p><w:r><w:continuationSeparator/></w:r></w:p>
        </w:footnote>
        """

        // Actual footnotes (IDs start at 1)
        for (i, note) in footnotes.enumerated() {
            let escaped = xmlEscape(note)
            entries += """
            <w:footnote w:id="\(i + 1)">
                <w:p>
                    <w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr>
                    <w:r>
                        <w:rPr><w:rStyle w:val="FootnoteReference"/><w:vertAlign w:val="superscript"/></w:rPr>
                        <w:footnoteRef/>
                    </w:r>
                    <w:r>
                        <w:rPr><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>
                        <w:t xml:space="preserve"> \(escaped)</w:t>
                    </w:r>
                </w:p>
            </w:footnote>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            \(entries)
        </w:footnotes>
        """
    }

    // MARK: - Markdown Parsing

    private enum TextBlock {
        case heading(String)
        case body(String)
        case figure(String)
    }

    private static func parseMarkdown(_ text: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        var currentParagraph = ""

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                if !currentParagraph.isEmpty {
                    blocks.append(.body(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                let heading = String(trimmed.dropFirst(3))
                blocks.append(.heading(heading))
            } else if trimmed.hasPrefix("[Figure") || trimmed.hasPrefix("[Fig") {
                if !currentParagraph.isEmpty {
                    blocks.append(.body(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                blocks.append(.figure(trimmed))
            } else if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    blocks.append(.body(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
            } else {
                if !currentParagraph.isEmpty {
                    currentParagraph += " "
                }
                currentParagraph += trimmed
            }
        }

        if !currentParagraph.isEmpty {
            blocks.append(.body(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return blocks
    }

    // MARK: - XML Helpers

    private static func paragraph(
        text: String,
        style: String? = nil,
        alignment: String? = nil,
        bold: Bool = false,
        italic: Bool = false,
        fontSize: Int = 20
    ) -> String {
        let escaped = xmlEscape(text)

        var pPr = ""
        if style != nil || alignment != nil {
            pPr += "<w:pPr>"
            if let style = style {
                pPr += "<w:pStyle w:val=\"\(style)\"/>"
            }
            if let alignment = alignment {
                pPr += "<w:jc w:val=\"\(alignment)\"/>"
            }
            pPr += "</w:pPr>"
        }

        var rPr = "<w:rPr>"
        rPr += "<w:sz w:val=\"\(fontSize)\"/><w:szCs w:val=\"\(fontSize)\"/>"
        if bold { rPr += "<w:b/>" }
        if italic { rPr += "<w:i/>" }
        rPr += "</w:rPr>"

        return "<w:p>\(pPr)<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>\n"
    }

    private static func paragraphWithFootnote(
        text: String,
        footnoteId: Int,
        style: String? = nil,
        alignment: String? = nil,
        fontSize: Int = 20
    ) -> String {
        let escaped = xmlEscape(text)

        var pPr = ""
        if style != nil || alignment != nil {
            pPr += "<w:pPr>"
            if let style = style { pPr += "<w:pStyle w:val=\"\(style)\"/>" }
            if let alignment = alignment { pPr += "<w:jc w:val=\"\(alignment)\"/>" }
            pPr += "</w:pPr>"
        }

        let rPr = "<w:rPr><w:sz w:val=\"\(fontSize)\"/><w:szCs w:val=\"\(fontSize)\"/></w:rPr>"
        let fnRef = """
        <w:r><w:rPr><w:rStyle w:val="FootnoteReference"/><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteReference w:id="\(footnoteId)"/></w:r>
        """

        return "<w:p>\(pPr)<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>\(fnRef)</w:p>\n"
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Supporting XML Files

    private static func buildStylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
                <w:name w:val="Normal"/>
                <w:rPr>
                    <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
                    <w:sz w:val="20"/>
                    <w:szCs w:val="20"/>
                </w:rPr>
            </w:style>
            <w:style w:type="paragraph" w:styleId="Title">
                <w:name w:val="Title"/>
                <w:basedOn w:val="Normal"/>
                <w:pPr><w:jc w:val="center"/><w:spacing w:after="200"/></w:pPr>
                <w:rPr>
                    <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
                    <w:b/>
                    <w:sz w:val="32"/>
                    <w:szCs w:val="32"/>
                </w:rPr>
            </w:style>
            <w:style w:type="paragraph" w:styleId="Heading2">
                <w:name w:val="heading 2"/>
                <w:basedOn w:val="Normal"/>
                <w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
                <w:rPr>
                    <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
                    <w:b/>
                    <w:sz w:val="22"/>
                    <w:szCs w:val="22"/>
                </w:rPr>
            </w:style>
            <w:style w:type="paragraph" w:styleId="FootnoteText">
                <w:name w:val="footnote text"/>
                <w:basedOn w:val="Normal"/>
                <w:rPr>
                    <w:sz w:val="16"/>
                    <w:szCs w:val="16"/>
                </w:rPr>
            </w:style>
            <w:style w:type="character" w:styleId="FootnoteReference">
                <w:name w:val="footnote reference"/>
                <w:rPr>
                    <w:vertAlign w:val="superscript"/>
                </w:rPr>
            </w:style>
        </w:styles>
        """
    }

    private static func buildContentTypesXML(hasFootnotes: Bool) -> String {
        var overrides = """
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        """
        if hasFootnotes {
            overrides += """
                <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            \(overrides)
        </Types>
        """
    }

    private static func buildRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private static func buildDocumentRelsXML(hasFootnotes: Bool) -> String {
        var rels = """
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        if hasFootnotes {
            rels += """
                <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            \(rels)
        </Relationships>
        """
    }
}

// MARK: - Minimal ZIP Writer (no external dependencies)

struct ZIPWriter {
    private var entries: [(name: String, data: Data)] = []

    mutating func addEntry(name: String, data: Data) {
        entries.append((name, data))
    }

    func write() -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(archive.count))
            let nameData = entry.name.data(using: .utf8)!
            let crc = crc32(entry.data)

            // Local file header
            appendUInt32(&archive, 0x04034B50)
            appendUInt16(&archive, 20)
            appendUInt16(&archive, 0)
            appendUInt16(&archive, 0)             // stored (no compression)
            appendUInt16(&archive, 0)
            appendUInt16(&archive, 0)
            appendUInt32(&archive, crc)
            appendUInt32(&archive, UInt32(entry.data.count))
            appendUInt32(&archive, UInt32(entry.data.count))
            appendUInt16(&archive, UInt16(nameData.count))
            appendUInt16(&archive, 0)
            archive.append(nameData)
            archive.append(entry.data)

            // Central directory entry
            appendUInt32(&centralDirectory, 0x02014B50)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt32(&centralDirectory, crc)
            appendUInt32(&centralDirectory, UInt32(entry.data.count))
            appendUInt32(&centralDirectory, UInt32(entry.data.count))
            appendUInt16(&centralDirectory, UInt16(nameData.count))
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt32(&centralDirectory, 0)
            appendUInt32(&centralDirectory, offsets.last!)
            centralDirectory.append(nameData)
        }

        let centralDirOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory
        appendUInt32(&archive, 0x06054B50)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, UInt16(entries.count))
        appendUInt16(&archive, UInt16(entries.count))
        appendUInt32(&archive, UInt32(centralDirectory.count))
        appendUInt32(&archive, centralDirOffset)
        appendUInt16(&archive, 0)

        return archive
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }
}
