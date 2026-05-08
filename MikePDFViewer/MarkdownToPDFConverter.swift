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
    /// Strategy: MarkdownToHTML emits clean body HTML → wrap with styled CSS
    /// template → render via shared HTMLToPDFRenderer. Side effect: writes the
    /// rendered PDF to TempFolderManager.tmpFolder.
    static func convert(source: String, sourceURL: URL) async throws -> (document: PDFDocument, tempPDFURL: URL) {
        let bodyHTML = MarkdownToHTML.renderHTML(source)
        let wrapped = wrapHTML(bodyHTML, title: sourceURL.lastPathComponent)
        let pdfData = try await HTMLToPDFRenderer.render(html: wrapped, loadExternalImages: false)

        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }

        let tempURL = try TempFolderManager.writeToTemp(data: pdfData, sourceURL: sourceURL)
        return (document, tempURL)
    }

    // MARK: - HTML wrapper

    private static func wrapHTML(_ body: String, title: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(MarkdownToHTML.htmlEscape(title))</title>
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
