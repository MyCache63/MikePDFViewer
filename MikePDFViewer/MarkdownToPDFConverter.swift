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
