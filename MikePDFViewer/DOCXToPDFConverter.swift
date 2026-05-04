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
            htmlBody = String(data: htmlData, encoding: .utf8) ?? ""
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

    /// NSAttributedString's HTML output already includes a <html><head>...<body> wrapper with
    /// inline styles. We inject a small @page margin rule to give PDF output proper margins,
    /// and override fixed pixel dimensions that confuse WKWebView's print layout.
    private static func wrapHTML(_ rawHTML: String, sourceFilename: String) -> String {
        let pageStyle = """
        <style>
        @page { margin: 0.5in; }
        body { margin: 0; padding: 0; font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; }
        img { max-width: 100%; height: auto; }
        table { max-width: 100%; }
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
