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
    /// Strategy: AttributedString(markdown:) → NSAttributedString → HTML data → wrap with
    /// styled CSS template → render via shared HTMLToPDFRenderer.
    /// Side effect: also writes the rendered PDF to TempFolderManager.tmpFolder.
    static func convert(source: String, sourceURL: URL) async throws -> (document: PDFDocument, tempPDFURL: URL) {
        let bodyHTML = try generateHTML(from: source)
        let wrapped = wrapHTML(bodyHTML, title: sourceURL.lastPathComponent)
        let pdfData = try await HTMLToPDFRenderer.render(html: wrapped, loadExternalImages: false)

        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }

        let tempURL = try TempFolderManager.writeToTemp(data: pdfData, sourceURL: sourceURL)
        return (document, tempURL)
    }

    /// Build HTML for the markdown body. Uses NSAttributedString's HTML serializer over
    /// an AttributedString-parsed markdown to preserve styling cues.
    private static func generateHTML(from source: String) throws -> String {
        let parseOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        let attr: AttributedString
        do {
            attr = try AttributedString(markdown: source, options: parseOptions)
        } catch {
            // If markdown parsing fails entirely, render as preformatted plain text.
            return "<pre>\(htmlEscape(source))</pre>"
        }

        let nsAttr = NSAttributedString(attr)
        do {
            let htmlData = try nsAttr.data(
                from: NSRange(location: 0, length: nsAttr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
            let full = String(data: htmlData, encoding: .utf8) ?? ""

            // Strip the AppKit-generated <html><head>...<body> wrapper so we can use ours.
            return extractBodyContent(from: full)
        } catch {
            throw ConversionError.htmlConversionFailed
        }
    }

    private static func extractBodyContent(from html: String) -> String {
        if let openRange = html.range(of: "<body", options: .caseInsensitive),
           let openTagEnd = html.range(of: ">", range: openRange.upperBound..<html.endIndex),
           let closeRange = html.range(of: "</body>", options: .caseInsensitive) {
            return String(html[openTagEnd.upperBound..<closeRange.lowerBound])
        }
        return html
    }

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
                    font-size: 13pt;
                    line-height: 1.55;
                    color: #1a1a1a;
                    margin: 0;
                    padding: 0;
                }
                h1 { font-size: 22pt; margin-top: 0.4em; margin-bottom: 0.5em; color: #000; }
                h2 { font-size: 18pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #000; }
                h3 { font-size: 15pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #222; }
                h4, h5, h6 { font-size: 13pt; margin-top: 1.0em; margin-bottom: 0.4em; color: #333; }
                p { margin: 0.5em 0; }
                code {
                    font-family: "SF Mono", Menlo, Consolas, monospace;
                    font-size: 11.5pt;
                    background: #f4f4f4;
                    padding: 1px 4px;
                    border-radius: 3px;
                }
                pre {
                    font-family: "SF Mono", Menlo, Consolas, monospace;
                    font-size: 11pt;
                    background: #f4f4f4;
                    padding: 12px;
                    border-radius: 4px;
                    overflow-x: auto;
                    line-height: 1.4;
                }
                pre code { background: transparent; padding: 0; }
                blockquote {
                    border-left: 3px solid #888;
                    padding-left: 12px;
                    margin: 0.6em 0;
                    color: #555;
                    font-style: italic;
                }
                ul, ol { margin: 0.5em 0 0.5em 1.2em; padding-left: 0.5em; }
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

    private static func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
