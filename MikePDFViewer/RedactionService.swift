import Foundation
import PDFKit
import AppKit

struct RedactionService {
    /// Apply redaction to selected areas on a page.
    /// This permanently removes content by:
    /// 1. Adding black rectangles over redaction areas
    /// 2. Flattening the page to an image (destroying underlying text)
    /// 3. Replacing the page with the flattened image
    static func redactAreas(on page: PDFPage, areas: [CGRect], in document: PDFDocument) -> Bool {
        guard let pageIndex = document.index(for: page) as Int? else { return false }

        // Draw black rectangles over the redaction areas
        for area in areas {
            let annotation = PDFAnnotation(bounds: area, forType: .square, withProperties: nil)
            annotation.color = .black
            annotation.interiorColor = .black
            page.addAnnotation(annotation)
        }

        // Flatten the page to image at 300 DPI to permanently burn in redactions
        guard let image = PageRenderer.renderPage(page, dpi: 300) else { return false }

        let originalSize = page.bounds(for: .mediaBox).size
        guard let newPage = PageRenderer.pageFromImage(image, originalPageSize: originalSize) else { return false }

        // Replace the page
        document.removePage(at: pageIndex)
        document.insert(newPage, at: pageIndex)

        return true
    }

    /// Redact the currently selected text on a page
    static func redactSelection(_ selection: PDFSelection, in document: PDFDocument) -> Bool {
        // Group redaction areas by page
        var pageAreas: [PDFPage: [CGRect]] = [:]
        for lineSel in selection.selectionsByLine() {
            guard let page = lineSel.pages.first else { continue }
            let bounds = lineSel.bounds(for: page)
            pageAreas[page, default: []].append(bounds)
        }

        var success = true
        for (page, areas) in pageAreas {
            if !redactAreas(on: page, areas: areas, in: document) {
                success = false
            }
        }
        return success
    }
}
