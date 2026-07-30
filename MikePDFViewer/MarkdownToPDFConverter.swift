import Foundation
import AppKit
import PDFKit

@MainActor
public final class MarkdownToPDFConverter {

    public enum ConversionError: Error {
        case htmlConversionFailed
        case pdfRenderFailed
        case parsedDocumentInvalid
    }

    /// Convert a markdown source string into a PDFDocument, baking in the
    /// chosen reader theme and typography so the saved PDF matches what the
    /// user is seeing on screen.
    public static func convert(source: String,
                               sourceURL: URL,
                               theme: MarkdownReaderTheme = .github,
                               typography: MarkdownTypography = .default
    ) async throws -> (document: PDFDocument, tempPDFURL: URL) {
        let bodyHTML = MarkdownToHTML.renderHTML(source)
        // Reuse the same theme bundle the live reader uses, plus the user's
        // typography overrides. Add an @page margin so the PDF has print margins.
        let themedHTML = MarkdownReaderThemeBundle.html(
            body: bodyHTML,
            title: sourceURL.lastPathComponent,
            theme: theme,
            typography: typography,
            focusMode: false
        )
        let wrapped = injectPrintCSS(into: themedHTML)
        let pdfData = try await HTMLToPDFRenderer.render(html: wrapped, loadExternalImages: false)

        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }

        let tempURL = try TempFolderManager.writeToTemp(data: pdfData, sourceURL: sourceURL)
        return (document, tempURL)
    }

    /// Print-oriented conversion: real page breaks (multi-page PDF, via the
    /// paginated renderer), caller-chosen margins, and an optional zoom that
    /// shrinks the text for fit-to-N-pages. Margins come from NSPrintInfo, so
    /// no `@page` CSS here (the two would stack).
    public static func convertForPrint(source: String,
                                       sourceURL: URL,
                                       theme: MarkdownReaderTheme,
                                       typography: MarkdownTypography,
                                       marginInches: Double,
                                       zoom: Double = 1.0
    ) async throws -> PDFDocument {
        let bodyHTML = MarkdownToHTML.renderHTML(source)
        let themedHTML = MarkdownReaderThemeBundle.html(
            body: bodyHTML,
            title: sourceURL.lastPathComponent,
            theme: theme,
            typography: typography,
            focusMode: false
        )
        let printStyle = """
        <style>
            .markdown-body { padding: 0 !important; max-width: 100% !important; }
            html { zoom: \(String(format: "%.3f", zoom)); }
        </style>
        """
        var wrapped = themedHTML
        if let headClose = wrapped.range(of: "</head>", options: .caseInsensitive) {
            wrapped.replaceSubrange(headClose, with: printStyle + "</head>")
        }
        let pdfData = try await PaginatedHTMLToPDF.render(html: wrapped, marginInches: marginInches)
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else {
            throw ConversionError.parsedDocumentInvalid
        }
        return document
    }

    /// Inject `@page` margin rule + a tighter content-area padding suitable
    /// for printed pages (the on-screen reader uses generous outer padding;
    /// the PDF gets it from `@page` instead).
    private static func injectPrintCSS(into html: String) -> String {
        let printStyle = """
        <style>
            @page { margin: 0.5in; }
            .markdown-body { padding: 0 !important; max-width: 100% !important; }
        </style>
        """
        if let headClose = html.range(of: "</head>", options: .caseInsensitive) {
            var output = html
            output.replaceSubrange(headClose, with: printStyle + "</head>")
            return output
        }
        return html
    }
}
