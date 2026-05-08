import Foundation
import AppKit
import PDFKit

@MainActor
final class DOCXToPDFConverter {

    enum ConversionError: Error {
        case docxReadFailed
        case htmlConversionFailed
        case pdfRenderFailed
        case parsedDocumentInvalid
    }

    /// Convert a .docx file to a PDFDocument.
    /// Strategy: NSAttributedString reads .docx → convert to HTML → render via shared HTMLToPDFRenderer.
    /// Side effect: also writes the rendered PDF to TempFolderManager.tmpFolder for save-as flows.
    static func convert(url: URL) async throws -> (document: PDFDocument, tempPDFURL: URL) {
        let attrStr: NSAttributedString
        do {
            attrStr = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
        } catch {
            throw ConversionError.docxReadFailed
        }

        let htmlBody: String
        do {
            let htmlData = try attrStr.data(
                from: NSRange(location: 0, length: attrStr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
            let raw = String(data: htmlData, encoding: .utf8) ?? ""
            htmlBody = scaleInlineFontSizes(in: raw, factor: 1.8)
        } catch {
            throw ConversionError.htmlConversionFailed
        }

        let wrapped = wrapHTML(htmlBody, sourceFilename: url.lastPathComponent)
        let pdfData = try await HTMLToPDFRenderer.render(html: wrapped, loadExternalImages: false)

        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }

        let tempURL = try TempFolderManager.writeToTemp(data: pdfData, sourceURL: url)
        return (document, tempURL)
    }

    /// NSAttributedString's HTML serializer emits inline styles like
    /// `font: 12.0px 'Calibri'` on every paragraph. Those inline declarations win over
    /// any stylesheet rules, so we can't bump the body font via CSS — we have to rewrite
    /// the inline declarations themselves. Scaling all sizes by a constant preserves the
    /// relative heading hierarchy while making body text readable on a US Letter page.
    private static func scaleInlineFontSizes(in html: String, factor: Double) -> String {
        let pattern = #"font:\s*([\d.]+)(px|pt)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }
        let nsString = html as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: html, options: [], range: fullRange)

        let mutable = NSMutableString(string: html)
        for match in matches.reversed() {
            let sizeStr = nsString.substring(with: match.range(at: 1))
            let unit = nsString.substring(with: match.range(at: 2))
            guard let size = Double(sizeStr) else { continue }
            let scaled = String(format: "%.1f", size * factor)
            let replacement = "font: \(scaled)\(unit)"
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return mutable as String
    }

    /// NSAttributedString's HTML output already includes a <html><head>...<body> wrapper with
    /// inline styles. We inject a small @page margin rule to give PDF output proper margins,
    /// and override fixed pixel dimensions that confuse WKWebView's print layout.
    private static func wrapHTML(_ rawHTML: String, sourceFilename: String) -> String {
        let pageStyle = """
        <style>
        @page { margin: 0.5in; }
        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 12pt;
            line-height: 1.45;
        }
        p { margin: 0.4em 0; }
        img { max-width: 100%; height: auto; }
        table { max-width: 100%; border-collapse: collapse; margin: 0.6em 0; }
        td, th { border: 1px solid #c0c0c0; padding: 4px 8px; vertical-align: top; }
        /* Word docs that use plain bold lines instead of Heading styles get
           heading-like rendering: a paragraph whose only child is <b> looks
           visually distinct from body text. */
        p > b:only-child {
            display: block;
            font-size: 1.35em !important;
            margin-top: 0.7em !important;
            margin-bottom: 0.3em !important;
            color: #000;
        }
        </style>
        """

        // Inject our @page style just before </head> if a <head> already exists,
        // otherwise prepend the full wrapper.
        if let headCloseRange = rawHTML.range(of: "</head>", options: .caseInsensitive) {
            var output = rawHTML
            output.replaceSubrange(headCloseRange, with: pageStyle + "</head>")
            return output
        }

        // Fallback: NSAttributedString didn't emit a <head> — wrap manually.
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <title>\(sourceFilename)</title>
        \(pageStyle)
        </head>
        <body>\(rawHTML)</body>
        </html>
        """
    }
}
