import Foundation
import PDFKit
import AppKit

struct WatermarkConfig {
    var text: String = "CONFIDENTIAL"
    var fontSize: CGFloat = 60
    var color: NSColor = .gray
    var opacity: CGFloat = 0.3
    var rotation: CGFloat = -45
}

struct WatermarkService {
    /// Apply a text watermark to all pages of a document
    static func applyWatermark(to document: PDFDocument, config: WatermarkConfig) {
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            let annotation = WatermarkAnnotation(
                bounds: bounds,
                text: config.text,
                fontSize: config.fontSize,
                color: config.color.withAlphaComponent(config.opacity),
                rotation: config.rotation
            )
            page.addAnnotation(annotation)
        }
    }
}

class WatermarkAnnotation: PDFAnnotation {
    private let text: String
    private let fontSize: CGFloat
    private let textColor: NSColor
    private let textRotation: CGFloat

    init(bounds: CGRect, text: String, fontSize: CGFloat, color: NSColor, rotation: CGFloat) {
        self.text = text
        self.fontSize = fontSize
        self.textColor = color
        self.textRotation = rotation
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)
        self.color = .clear
    }

    required init?(coder: NSCoder) {
        self.text = ""
        self.fontSize = 60
        self.textColor = .gray
        self.textRotation = -45
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()

        // Move to center and rotate
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: textRotation * .pi / 180)

        // Draw text centered
        let textRect = CGRect(
            x: -textSize.width / 2,
            y: -textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)

        context.restoreGState()
    }
}
