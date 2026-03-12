import SwiftUI
import PDFKit

extension Notification.Name {
    static let pdfZoomIn = Notification.Name("pdfZoomIn")
    static let pdfZoomOut = Notification.Name("pdfZoomOut")
    static let pdfZoomFit = Notification.Name("pdfZoomFit")
    static let pdfRotateRight = Notification.Name("pdfRotateRight")
    static let pdfRotateLeft = Notification.Name("pdfRotateLeft")
    static let pdfCopy = Notification.Name("pdfCopy")
    static let pdfDocumentModified = Notification.Name("pdfDocumentModified")
    static let pdfToggleDarkMode = Notification.Name("pdfToggleDarkMode")
    static let pdfSetDisplayMode = Notification.Name("pdfSetDisplayMode")
    static let pdfApplyHighlight = Notification.Name("pdfApplyHighlight")
    static let pdfApplyUnderline = Notification.Name("pdfApplyUnderline")
    static let pdfApplyStrikethrough = Notification.Name("pdfApplyStrikethrough")
    static let pdfAddStickyNote = Notification.Name("pdfAddStickyNote")
    static let pdfAddFreeText = Notification.Name("pdfAddFreeText")
    static let pdfToggleBookmark = Notification.Name("pdfToggleBookmark")
    static let pdfExtractPages = Notification.Name("pdfExtractPages")
    static let pdfOpenFile = Notification.Name("pdfOpenFile")
    static let pdfToggleSplitView = Notification.Name("pdfToggleSplitView")
    static let pdfStartPresentation = Notification.Name("pdfStartPresentation")
    static let pdfShowMerge = Notification.Name("pdfShowMerge")
    static let pdfApplySignature = Notification.Name("pdfApplySignature")
    static let pdfRedactSelection = Notification.Name("pdfRedactSelection")
    static let pdfPrint = Notification.Name("pdfPrint")
}

// MARK: - Custom PDFView with print support and signature placement

class PrintablePDFView: PDFView {
    var pendingSignatureImage: NSImage?

    // Respond to macOS system print action (File > Print / Cmd+P)
    @objc override func printView(_ sender: Any?) {
        performPrint()
    }

    // Also respond to printDocument: for NSDocument-style apps
    @objc func printDocument(_ sender: Any?) {
        performPrint()
    }

    func performPrint() {
        guard let document = self.document else { return }
        let printInfo = NSPrintInfo.shared
        if let printOp = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) {
            printOp.showsPrintPanel = true
            printOp.showsProgressPanel = true
            if let window = self.window {
                printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            }
        }
    }

    /// Add annotation with undo support
    func addAnnotationWithUndo(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        undoManager?.registerUndo(withTarget: self) { target in
            page.removeAnnotation(annotation)
            NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
        }
        undoManager?.setActionName("Add Annotation")
        NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
    }

    override func mouseDown(with event: NSEvent) {
        // If we have a pending signature, place it where the user clicked
        if let sigImage = pendingSignatureImage {
            let viewPoint = convert(event.locationInWindow, from: nil)
            guard let page = page(for: viewPoint, nearest: true) else {
                super.mouseDown(with: event)
                return
            }
            let pagePoint = convert(viewPoint, to: page)

            let sigWidth: CGFloat = 150
            let sigHeight = sigWidth * (sigImage.size.height / max(sigImage.size.width, 1))
            let bounds = CGRect(
                x: pagePoint.x - sigWidth / 2,
                y: pagePoint.y - sigHeight / 2,
                width: sigWidth,
                height: sigHeight
            )

            let annotation = SignatureAnnotation(bounds: bounds, image: sigImage)
            addAnnotationWithUndo(annotation, to: page)
            pendingSignatureImage = nil
            NSCursor.arrow.set()
            return
        }

        super.mouseDown(with: event)
    }

    // Show crosshair cursor when in signature placement mode
    override func resetCursorRects() {
        super.resetCursorRects()
        if pendingSignatureImage != nil {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}

// MARK: - PDFKitView

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let searchText: String
    let darkMode: Bool
    let displayMode: PDFDisplayMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PrintablePDFView {
        let pdfView = PrintablePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = displayMode
        pdfView.displayDirection = .vertical
        pdfView.document = document

        // Dark mode layer setup
        pdfView.wantsLayer = true
        if darkMode {
            pdfView.layer?.filters = [CIFilter(name: "CIColorInvert")!]
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PrintablePDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        if let page = document.page(at: currentPage),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        // Update display mode
        if pdfView.displayMode != displayMode {
            pdfView.displayMode = displayMode
        }

        // Update dark mode
        let currentlyDark = !(pdfView.layer?.filters?.isEmpty ?? true)
        if darkMode != currentlyDark {
            if darkMode {
                pdfView.layer?.filters = [CIFilter(name: "CIColorInvert")!]
            } else {
                pdfView.layer?.filters = []
            }
        }

        context.coordinator.search(searchText, in: pdfView)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PrintablePDFView?
        private var lastSearchText = ""

        init(_ parent: PDFKitView) {
            self.parent = parent
            super.init()

            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(handleZoomIn), name: .pdfZoomIn, object: nil)
            nc.addObserver(self, selector: #selector(handleZoomOut), name: .pdfZoomOut, object: nil)
            nc.addObserver(self, selector: #selector(handleZoomFit), name: .pdfZoomFit, object: nil)
            nc.addObserver(self, selector: #selector(handleRotateRight), name: .pdfRotateRight, object: nil)
            nc.addObserver(self, selector: #selector(handleRotateLeft), name: .pdfRotateLeft, object: nil)
            nc.addObserver(self, selector: #selector(handleCopy), name: .pdfCopy, object: nil)
            nc.addObserver(self, selector: #selector(handleHighlight), name: .pdfApplyHighlight, object: nil)
            nc.addObserver(self, selector: #selector(handleUnderline), name: .pdfApplyUnderline, object: nil)
            nc.addObserver(self, selector: #selector(handleStrikethrough), name: .pdfApplyStrikethrough, object: nil)
            nc.addObserver(self, selector: #selector(handleAddStickyNote), name: .pdfAddStickyNote, object: nil)
            nc.addObserver(self, selector: #selector(handleAddFreeText), name: .pdfAddFreeText, object: nil)
            nc.addObserver(self, selector: #selector(handleApplySignature), name: .pdfApplySignature, object: nil)
            nc.addObserver(self, selector: #selector(handleRedactSelection), name: .pdfRedactSelection, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let pageIndex = pdfView.document?.index(for: currentPage) else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }

        @objc func handleZoomIn(_ notification: Notification) {
            pdfView?.zoomIn(nil)
        }

        @objc func handleZoomOut(_ notification: Notification) {
            pdfView?.zoomOut(nil)
        }

        @objc func handleZoomFit(_ notification: Notification) {
            pdfView?.autoScales = true
        }

        @objc func handleRotateRight(_ notification: Notification) {
            guard let page = pdfView?.currentPage else { return }
            page.rotation = (page.rotation + 90) % 360
            pdfView?.layoutDocumentView()
            NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
        }

        @objc func handleRotateLeft(_ notification: Notification) {
            guard let page = pdfView?.currentPage else { return }
            page.rotation = (page.rotation + 270) % 360
            pdfView?.layoutDocumentView()
            NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
        }

        @objc func handleCopy(_ notification: Notification) {
            pdfView?.copy(nil)
        }

        @objc func handleHighlight(_ notification: Notification) {
            applyTextMarkup(.highlight, from: notification)
        }

        @objc func handleUnderline(_ notification: Notification) {
            applyTextMarkup(.underline, from: notification)
        }

        @objc func handleStrikethrough(_ notification: Notification) {
            applyTextMarkup(.strikeOut, from: notification)
        }

        private func applyTextMarkup(_ type: PDFAnnotationSubtype, from notification: Notification) {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection else { return }
            let color = notification.userInfo?["color"] as? NSColor ?? .yellow

            for lineSel in selection.selectionsByLine() {
                guard let page = lineSel.pages.first else { continue }
                let bounds = lineSel.bounds(for: page)
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                pdfView.addAnnotationWithUndo(annotation, to: page)
            }
            pdfView.clearSelection()
        }

        @objc func handleAddStickyNote(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let page = pdfView.currentPage else { return }
            let text = notification.userInfo?["text"] as? String ?? ""
            let color = notification.userInfo?["color"] as? NSColor ?? .yellow

            let visibleRect = pdfView.convert(pdfView.visibleRect, to: page)
            let noteSize: CGFloat = 20
            let bounds = CGRect(
                x: visibleRect.midX - noteSize / 2,
                y: visibleRect.midY - noteSize / 2,
                width: noteSize,
                height: noteSize
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
            annotation.contents = text
            annotation.color = color
            pdfView.addAnnotationWithUndo(annotation, to: page)
        }

        @objc func handleAddFreeText(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let page = pdfView.currentPage else { return }
            let text = notification.userInfo?["text"] as? String ?? ""

            let visibleRect = pdfView.convert(pdfView.visibleRect, to: page)
            let bounds = CGRect(
                x: visibleRect.midX - 100,
                y: visibleRect.midY - 20,
                width: 200,
                height: 40
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = NSFont.systemFont(ofSize: 14)
            annotation.fontColor = .black
            annotation.color = .clear
            pdfView.addAnnotationWithUndo(annotation, to: page)
        }

        @objc func handleApplySignature(_ notification: Notification) {
            guard let pdfView = pdfView else { return }

            // Handle cancel
            if notification.userInfo?["cancel"] as? Bool == true {
                pdfView.pendingSignatureImage = nil
                NSCursor.arrow.set()
                pdfView.window?.invalidateCursorRects(for: pdfView)
                return
            }

            guard let image = notification.userInfo?["image"] as? NSImage else { return }

            // Enter signature placement mode — next click places it
            pdfView.pendingSignatureImage = image
            NSCursor.crosshair.set()
            pdfView.window?.invalidateCursorRects(for: pdfView)
        }

        @objc func handleRedactSelection(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let document = pdfView.document else { return }

            let success = RedactionService.redactSelection(selection, in: document)
            if success {
                pdfView.clearSelection()
                NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
            }
        }

        func search(_ text: String, in pdfView: PDFView) {
            guard text != lastSearchText else { return }
            lastSearchText = text

            pdfView.highlightedSelections = nil

            guard !text.isEmpty, let document = pdfView.document else { return }

            let selections = document.findString(text, withOptions: .caseInsensitive)
            if !selections.isEmpty {
                pdfView.highlightedSelections = selections
                if let first = selections.first {
                    pdfView.go(to: first)
                }
            }
        }
    }
}

// MARK: - Signature Annotation

class SignatureAnnotation: PDFAnnotation {
    private var signatureImage: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.signatureImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        self.signatureImage = NSImage()
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        super.draw(with: box, in: context)

        guard let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.draw(cgImage, in: bounds)
    }
}
