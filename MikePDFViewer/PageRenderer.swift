import Foundation
import PDFKit
import AppKit

struct PageRenderer {
    /// Render a PDF page to an NSImage at the specified DPI
    static func renderPage(_ page: PDFPage, dpi: CGFloat = 300) -> NSImage? {
        let mediaBox = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = mediaBox.width * scale
        let height = mediaBox.height * scale
        let size = CGSize(width: width, height: height)

        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)

        // Apply page rotation
        let rotation = page.rotation
        switch rotation {
        case 90:
            context.translateBy(x: mediaBox.height, y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: mediaBox.width, y: mediaBox.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: mediaBox.width)
            context.rotate(by: -.pi / 2)
        default:
            break
        }

        page.draw(with: .mediaBox, to: context)
        image.unlockFocus()
        return image
    }

    /// Render a PDF page to PNG data at the specified DPI
    static func renderPageToPNG(_ page: PDFPage, dpi: CGFloat = 300) -> Data? {
        guard let image = renderPage(page, dpi: dpi) else { return nil }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Render a PDF page to JPEG data at the specified DPI and quality
    static func renderPageToJPEG(_ page: PDFPage, dpi: CGFloat = 300, quality: Double = 0.85) -> Data? {
        guard let image = renderPage(page, dpi: dpi) else { return nil }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Create a new PDFPage from an image
    static func pageFromImage(_ image: NSImage, originalPageSize: CGSize) -> PDFPage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        // Create a PDF page from the image data by drawing into a PDF context
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: originalPageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        pdfContext.beginPage(mediaBox: &mediaBox)

        if let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            pdfContext.draw(cgImage, in: mediaBox)
        }

        pdfContext.endPage()
        pdfContext.closePDF()

        guard let newDoc = PDFDocument(data: pdfData as Data),
              let newPage = newDoc.page(at: 0) else { return nil }
        return newPage
    }
}
