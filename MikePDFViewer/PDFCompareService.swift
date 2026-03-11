import Foundation
import PDFKit
import AppKit

struct PDFCompareResult {
    let page1Image: NSImage
    let page2Image: NSImage
    let diffImage: NSImage
    let diffPercentage: Double
}

struct PDFCompareService {
    /// Compare two pages pixel-by-pixel and generate a difference overlay
    static func comparePages(page1: PDFPage, page2: PDFPage, dpi: CGFloat = 150, sensitivity: CGFloat = 30) -> PDFCompareResult? {
        guard let img1 = PageRenderer.renderPage(page1, dpi: dpi),
              let img2 = PageRenderer.renderPage(page2, dpi: dpi) else { return nil }

        guard let tiff1 = img1.tiffRepresentation,
              let tiff2 = img2.tiffRepresentation,
              let bitmap1 = NSBitmapImageRep(data: tiff1),
              let bitmap2 = NSBitmapImageRep(data: tiff2) else { return nil }

        let width = min(bitmap1.pixelsWide, bitmap2.pixelsWide)
        let height = min(bitmap1.pixelsHigh, bitmap2.pixelsHigh)

        let diffImage = NSImage(size: NSSize(width: width, height: height))
        diffImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            diffImage.unlockFocus()
            return nil
        }

        // Draw page 1 as base
        if let cg1 = bitmap1.cgImage {
            context.draw(cg1, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Compare pixels and overlay differences in red
        var diffCount = 0
        let totalPixels = width * height
        let thresh = Int(sensitivity)

        for y in 0..<height {
            for x in 0..<width {
                let c1 = bitmap1.colorAt(x: x, y: y) ?? .white
                let c2 = bitmap2.colorAt(x: x, y: y) ?? .white

                let r1 = Int(c1.redComponent * 255)
                let g1 = Int(c1.greenComponent * 255)
                let b1 = Int(c1.blueComponent * 255)
                let r2 = Int(c2.redComponent * 255)
                let g2 = Int(c2.greenComponent * 255)
                let b2 = Int(c2.blueComponent * 255)

                let diff = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
                if diff > thresh {
                    diffCount += 1
                    context.setFillColor(NSColor.red.withAlphaComponent(0.4).cgColor)
                    context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
                }
            }
        }

        diffImage.unlockFocus()

        let pct = totalPixels > 0 ? (Double(diffCount) / Double(totalPixels)) * 100 : 0

        return PDFCompareResult(
            page1Image: img1,
            page2Image: img2,
            diffImage: diffImage,
            diffPercentage: pct
        )
    }
}
