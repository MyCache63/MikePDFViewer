import Foundation
import PDFKit
import Vision
import CoreText

/// Makes scanned PDFs searchable using Apple's on-device Vision OCR
/// (VNRecognizeTextRequest). Pages with no selectable text get an invisible,
/// selectable text layer drawn over the original content, so Cmd+F, text
/// selection, and copy work on scans. Runs entirely on-device: no API key,
/// no network, free.
///
/// This is separate from OCRService (the LLM-based transcription tool):
/// that one extracts text OUT of a document; this one puts a text layer
/// INTO the document.
///
/// Invisible-text technique adapted from mac-ocr (MIT license):
/// https://github.com/privatenumber/mac-ocr
/// Key points borrowed: text drawing mode .invisible, one text run per
/// recognized word (line-level fallback), identity text matrix (a scaled
/// text matrix makes extractors read "Hello" as "H e l l o", breaking
/// search), font size equal to the recognized box height.
enum SearchableOCRService {

    struct OCRResult {
        let data: Data
        let ocrPageCount: Int
    }

    enum ServiceError: LocalizedError, Equatable {
        case noPages
        case alreadySearchable
        case contextFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noPages: return "The document has no pages."
            case .alreadySearchable: return "Every page already has searchable text. Nothing to do."
            case .contextFailed: return "Could not create the output PDF."
            case .cancelled: return "OCR was cancelled. The document is unchanged."
            }
        }
    }

    /// Thread-safe cancellation token: the UI cancels from the main thread
    /// while the OCR loop polls from its background queue.
    final class CancelFlag {
        private let lock = NSLock()
        private var value = false

        func cancel() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Rebuilds the document with an invisible OCR text layer on pages that
    /// have none. Original page content is preserved as vectors (not
    /// rasterized); annotations are drawn into the page (they stay visible
    /// but are no longer separately editable).
    ///
    /// Blocking; call from a background task. `progress(done, total)` fires
    /// as pages complete, from the calling thread.
    static func makeSearchable(
        document: PDFDocument,
        cancelFlag: CancelFlag? = nil,
        progress: (Int, Int) -> Void
    ) throws -> OCRResult {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ServiceError.noPages }

        var needsOCR: [Bool] = []
        for i in 0..<pageCount {
            let text = document.page(at: i)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            needsOCR.append(text.isEmpty)
        }
        guard needsOCR.contains(true) else { throw ServiceError.alreadySearchable }

        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ServiceError.contextFailed
        }

        var ocrPageCount = 0
        progress(0, pageCount)

        for i in 0..<pageCount {
            if cancelFlag?.isCancelled == true {
                context.closePDF()
                throw ServiceError.cancelled
            }
            // Per-page autoreleasepool: each 300-dpi raster is ~34 MB, and
            // without a pool the autoreleased images for every page pile up
            // until the whole loop finishes.
            autoreleasepool {
                guard let page = document.page(at: i), let pageRef = page.pageRef else { return }

                let box = displayBox(for: pageRef)
                var mediaBox = box
                let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)

                // Visible layer: white background + original vector content,
                // rotated/cropped exactly as displayed, then annotations.
                let transform = pageRef.getDrawingTransform(
                    .cropBox, rect: box, rotate: 0, preserveAspectRatio: false
                )
                context.saveGState()
                context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                context.fill(box)
                context.concatenate(transform)
                context.drawPDFPage(pageRef)
                for annotation in page.annotations {
                    annotation.draw(with: .cropBox, in: context)
                }
                context.restoreGState()

                if needsOCR[i], let raster = renderRaster(pageRef: pageRef, displayBox: box, transform: transform) {
                    let observations = (try? recognizeText(in: raster)) ?? []
                    if !observations.isEmpty { ocrPageCount += 1 }
                    drawInvisibleTextLayer(observations, mediaBox: box, into: context)
                }

                context.endPDFPage()
            }
            progress(i + 1, pageCount)
        }

        context.closePDF()
        return OCRResult(data: outputData as Data, ocrPageCount: ocrPageCount)
    }

    // MARK: - Geometry

    /// The page rect as displayed: crop box with /Rotate applied.
    private static func displayBox(for page: CGPDFPage) -> CGRect {
        let cropBox = page.getBoxRect(.cropBox)
        let rotated = abs(Int(page.rotationAngle)) % 180 == 90
        return CGRect(
            x: 0, y: 0,
            width: rotated ? cropBox.height : cropBox.width,
            height: rotated ? cropBox.width : cropBox.height
        )
    }

    // MARK: - Rasterization for Vision

    private static func renderRaster(
        pageRef: CGPDFPage,
        displayBox: CGRect,
        transform: CGAffineTransform,
        dpi: CGFloat = 300
    ) -> CGImage? {
        guard displayBox.width > 0, displayBox.height > 0 else { return nil }
        // Cap the longest side so huge pages don't blow up memory; Vision
        // accuracy plateaus well below this.
        let maxDimension: CGFloat = 6000
        var scale = dpi / 72.0
        let longest = max(displayBox.width, displayBox.height) * scale
        if longest > maxDimension {
            scale *= maxDimension / longest
        }

        let width = Int((displayBox.width * scale).rounded(.up))
        let height = Int((displayBox.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(transform)
        ctx.drawPDFPage(pageRef)
        return ctx.makeImage()
    }

    // MARK: - Vision OCR

    private static func recognizeText(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    // MARK: - Invisible text layer

    private static func drawInvisibleTextLayer(
        _ observations: [VNRecognizedTextObservation],
        mediaBox: CGRect,
        into context: CGContext
    ) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            guard !text.isEmpty else { continue }

            // One run per word so selection rectangles track the printed
            // words. Vision gives a box per character range; fall back to a
            // single line-level run when word geometry fails.
            var drewWords = false
            for range in wordRanges(in: text) {
                guard let wordBox = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
                drawInvisibleText(String(text[range]), normalizedBox: wordBox, mediaBox: mediaBox, into: context)
                drewWords = true
            }
            if !drewWords {
                drawInvisibleText(text, normalizedBox: observation.boundingBox, mediaBox: mediaBox, into: context)
            }
        }

        context.restoreGState()
    }

    /// Ranges of non-whitespace runs, punctuation included ("$1,204.50"
    /// stays one token; enumerateSubstrings(.byWords) would strip it).
    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                if let s = start {
                    ranges.append(s..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
            index = text.index(after: index)
        }
        if let s = start {
            ranges.append(s..<text.endIndex)
        }
        return ranges
    }

    /// Vision bounding boxes are normalized with a bottom-left origin, same
    /// as PDF user space, so mapping is a straight scale into the media box.
    private static func drawInvisibleText(
        _ text: String,
        normalizedBox box: CGRect,
        mediaBox: CGRect,
        into context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let boxHeight = box.height * mediaBox.height
        guard boxHeight > 0 else { return }

        let originX = mediaBox.minX + box.minX * mediaBox.width
        let originY = mediaBox.minY + box.minY * mediaBox.height

        let font = makeFont(size: boxHeight)
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // Identity text matrix on purpose: scaling text to fit the box width
        // serializes per-glyph positions that PDF text extractors read as
        // spaces between letters, which breaks find. Width therefore stays
        // approximate within each word run.
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: originX, y: originY + descent)
        CTLineDraw(line, context)
    }

    private static func makeFont(size: CGFloat) -> CTFont {
        let clamped = max(size, 1)
        return CTFontCreateUIFontForLanguage(.system, clamped, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, clamped, nil)
    }
}
