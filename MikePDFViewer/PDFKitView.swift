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
    // Posted when annotation editing mode changes
    // userInfo: ["editing": Bool, "type": String, "text": String]
    static let pdfAnnotationEditingChanged = Notification.Name("pdfAnnotationEditingChanged")
}

// MARK: - Custom PDFView with print, annotation editing

class PrintablePDFView: PDFView {
    // Static reference for direct access from SwiftUI
    static weak var current: PrintablePDFView?
    // Cmd+P event monitor
    private static var printMonitor: Any?

    // Annotation editing state
    private(set) var activeAnnotation: PDFAnnotation?
    private var activePage: PDFPage?
    private var isDragging = false
    private var isResizing = false
    private var dragOffset: CGPoint = .zero
    private var resizeCorner: Int = -1
    private var initialBounds: CGRect = .zero
    private let handleHitSize: CGFloat = 14

    /// Types that support resizing (drag corners)
    private var activeAnnotationIsResizable: Bool {
        guard let ann = activeAnnotation else { return false }
        return ann is SignatureAnnotation || ann.type == "FreeText"
    }

    /// Types that have editable text
    private var activeAnnotationHasText: Bool {
        guard let ann = activeAnnotation else { return false }
        return ann.type == "Text" || ann.type == "FreeText"
    }

    // MARK: - Print

    @objc override func printView(_ sender: Any?) {
        performPrint()
    }

    @objc func printDocument(_ sender: Any?) {
        performPrint()
    }

    func performPrint() {
        guard let document = self.document else { return }
        let printInfo = NSPrintInfo.shared
        if let printOp = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) {
            printOp.showsPrintPanel = true
            printOp.showsProgressPanel = true
            if let window = self.window ?? NSApp.keyWindow {
                printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                // Last resort: run as modal dialog without a parent window
                printOp.run()
            }
        }
    }

    /// Reliable print that walks view hierarchy as fallback
    static func triggerPrint() {
        if let current = current {
            current.performPrint()
            return
        }
        // Fallback: find PrintablePDFView in the key window
        if let window = NSApp.keyWindow {
            findPDFView(in: window.contentView)?.performPrint()
        }
    }

    private static func findPDFView(in view: NSView?) -> PrintablePDFView? {
        guard let view = view else { return nil }
        if let pdfView = view as? PrintablePDFView { return pdfView }
        for subview in view.subviews {
            if let found = findPDFView(in: subview) { return found }
        }
        return nil
    }

    /// Install a Cmd+P event monitor at the app level
    static func installPrintMonitor() {
        guard printMonitor == nil else { return }
        printMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "p" {
                triggerPrint()
                return nil // consume the event
            }
            return event
        }
    }

    // MARK: - Undo

    func addAnnotationWithUndo(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        undoManager?.registerUndo(withTarget: self) { target in
            page.removeAnnotation(annotation)
            NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
        }
        undoManager?.setActionName("Add Annotation")
        NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
    }

    // MARK: - Annotation placement

    func placeSignature(image: NSImage) {
        guard let page = currentPage else { return }
        let visibleRect = convert(visibleRect, to: page)

        let sigWidth: CGFloat = 200
        let sigHeight = sigWidth * (image.size.height / max(image.size.width, 1))
        let bounds = CGRect(
            x: visibleRect.midX - sigWidth / 2,
            y: visibleRect.midY - sigHeight / 2,
            width: sigWidth,
            height: sigHeight
        )

        let annotation = SignatureAnnotation(bounds: bounds, image: image)
        annotation.isEditing = true
        addAnnotationWithUndo(annotation, to: page)
        startEditing(annotation, on: page, type: "signature")
    }

    func placeStickyNote(color: NSColor = .yellow) {
        guard let page = currentPage else { return }
        let visibleRect = convert(visibleRect, to: page)
        let noteSize: CGFloat = 24
        let bounds = CGRect(
            x: visibleRect.midX - noteSize / 2,
            y: visibleRect.midY - noteSize / 2,
            width: noteSize,
            height: noteSize
        )
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.contents = ""
        annotation.color = color
        addAnnotationWithUndo(annotation, to: page)
        startEditing(annotation, on: page, type: "stickyNote")
    }

    func placeFreeText() {
        guard let page = currentPage else { return }
        let visibleRect = convert(visibleRect, to: page)
        let bounds = CGRect(
            x: visibleRect.midX - 100,
            y: visibleRect.midY - 20,
            width: 200,
            height: 40
        )
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = ""
        annotation.font = NSFont.systemFont(ofSize: 14)
        annotation.fontColor = .black
        annotation.color = .white.withAlphaComponent(0.9)
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 1
        addAnnotationWithUndo(annotation, to: page)
        startEditing(annotation, on: page, type: "freeText")
    }

    // MARK: - Editing mode

    private func startEditing(_ annotation: PDFAnnotation, on page: PDFPage, type: String) {
        // Deselect previous if any
        if let prev = activeAnnotation as? SignatureAnnotation {
            prev.isEditing = false
        }
        activeAnnotation = annotation
        activePage = page
        if let sig = annotation as? SignatureAnnotation {
            sig.isEditing = true
        }
        setNeedsDisplay(bounds)

        NotificationCenter.default.post(
            name: .pdfAnnotationEditingChanged,
            object: nil,
            userInfo: [
                "editing": true,
                "type": type,
                "text": annotation.contents ?? ""
            ]
        )
    }

    func finalizeAnnotation() {
        if let sig = activeAnnotation as? SignatureAnnotation {
            sig.isEditing = false
        }
        activeAnnotation = nil
        activePage = nil
        isDragging = false
        isResizing = false
        setNeedsDisplay(bounds)
        NotificationCenter.default.post(
            name: .pdfAnnotationEditingChanged,
            object: nil,
            userInfo: ["editing": false, "type": "", "text": ""]
        )
    }

    func cancelAnnotation() {
        guard let ann = activeAnnotation, let page = activePage else { return }
        if let sig = ann as? SignatureAnnotation {
            sig.isEditing = false
        }
        page.removeAnnotation(ann)
        activeAnnotation = nil
        activePage = nil
        isDragging = false
        isResizing = false
        setNeedsDisplay(bounds)
        NotificationCenter.default.post(
            name: .pdfAnnotationEditingChanged,
            object: nil,
            userInfo: ["editing": false, "type": "", "text": ""]
        )
        NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
    }

    func updateActiveAnnotationText(_ text: String) {
        guard let ann = activeAnnotation else { return }
        ann.contents = text
        setNeedsDisplay(bounds)
    }

    // MARK: - Mouse handling for drag/resize

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else {
            super.mouseDown(with: event)
            return
        }
        let pagePoint = convert(viewPoint, to: page)

        // If editing an annotation, check for resize handles or drag
        if let active = activeAnnotation {
            // Check resize handles (corners) for resizable types
            if activeAnnotationIsResizable {
                let corners = [
                    CGPoint(x: active.bounds.minX, y: active.bounds.minY),
                    CGPoint(x: active.bounds.maxX, y: active.bounds.minY),
                    CGPoint(x: active.bounds.minX, y: active.bounds.maxY),
                    CGPoint(x: active.bounds.maxX, y: active.bounds.maxY),
                ]
                for (i, corner) in corners.enumerated() {
                    if abs(pagePoint.x - corner.x) < handleHitSize &&
                       abs(pagePoint.y - corner.y) < handleHitSize {
                        isResizing = true
                        resizeCorner = i
                        initialBounds = active.bounds
                        return
                    }
                }
            }

            // Check if clicking inside annotation to drag
            if active.bounds.contains(pagePoint) {
                isDragging = true
                dragOffset = CGPoint(
                    x: pagePoint.x - active.bounds.origin.x,
                    y: pagePoint.y - active.bounds.origin.y
                )
                return
            }

            // Clicked elsewhere — finalize
            finalizeAnnotation()
        }

        // Check if clicking on any movable annotation to select it
        for annotation in page.annotations {
            guard annotation.bounds.contains(pagePoint) else { continue }

            if let sigAnnotation = annotation as? SignatureAnnotation {
                sigAnnotation.isEditing = true
                startEditing(sigAnnotation, on: page, type: "signature")
                return
            }
            if annotation.type == "Text" {
                startEditing(annotation, on: page, type: "stickyNote")
                return
            }
            if annotation.type == "FreeText" {
                startEditing(annotation, on: page, type: "freeText")
                return
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let active = activeAnnotation, let page = activePage else {
            super.mouseDragged(with: event)
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = convert(viewPoint, to: page)

        if isDragging {
            let newOrigin = CGPoint(
                x: pagePoint.x - dragOffset.x,
                y: pagePoint.y - dragOffset.y
            )
            active.bounds = CGRect(origin: newOrigin, size: active.bounds.size)
            setNeedsDisplay(bounds)
        } else if isResizing {
            var newBounds = initialBounds
            let minW: CGFloat = 40
            let minH: CGFloat = 20

            switch resizeCorner {
            case 3: // TR
                newBounds.size.width = max(minW, pagePoint.x - initialBounds.minX)
                newBounds.size.height = max(minH, pagePoint.y - initialBounds.minY)
            case 1: // BR
                newBounds.size.width = max(minW, pagePoint.x - initialBounds.minX)
                let newH = max(minH, initialBounds.maxY - pagePoint.y)
                newBounds.origin.y = initialBounds.maxY - newH
                newBounds.size.height = newH
            case 2: // TL
                let newW = max(minW, initialBounds.maxX - pagePoint.x)
                newBounds.origin.x = initialBounds.maxX - newW
                newBounds.size.width = newW
                newBounds.size.height = max(minH, pagePoint.y - initialBounds.minY)
            case 0: // BL
                let newW = max(minW, initialBounds.maxX - pagePoint.x)
                let newH = max(minH, initialBounds.maxY - pagePoint.y)
                newBounds.origin.x = initialBounds.maxX - newW
                newBounds.origin.y = initialBounds.maxY - newH
                newBounds.size.width = newW
                newBounds.size.height = newH
            default:
                break
            }

            active.bounds = newBounds
            setNeedsDisplay(bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging || isResizing {
            isDragging = false
            isResizing = false
        } else {
            super.mouseUp(with: event)
        }
    }

    // Draw selection handles for non-signature active annotations
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw selection handles for non-signature annotations (signatures draw their own)
        guard let active = activeAnnotation,
              !(active is SignatureAnnotation),
              let page = activePage else { return }

        // Convert annotation bounds from page space to view space
        let pageBounds = active.bounds
        let viewBounds = convert(pageBounds, from: page)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dashed selection border
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(viewBounds)

        // Corner handles (only for resizable types)
        if activeAnnotationIsResizable {
            let handleSize: CGFloat = 8
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)

            let corners = [
                CGPoint(x: viewBounds.minX, y: viewBounds.minY),
                CGPoint(x: viewBounds.maxX, y: viewBounds.minY),
                CGPoint(x: viewBounds.minX, y: viewBounds.maxY),
                CGPoint(x: viewBounds.maxX, y: viewBounds.maxY),
            ]
            for corner in corners {
                let rect = CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            }
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
        PrintablePDFView.current = pdfView
        PrintablePDFView.installPrintMonitor()
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

        if pdfView.displayMode != displayMode {
            pdfView.displayMode = displayMode
        }

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

        @objc func handleZoomIn(_ notification: Notification) { pdfView?.zoomIn(nil) }
        @objc func handleZoomOut(_ notification: Notification) { pdfView?.zoomOut(nil) }
        @objc func handleZoomFit(_ notification: Notification) { pdfView?.autoScales = true }

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

        @objc func handleCopy(_ notification: Notification) { pdfView?.copy(nil) }

        @objc func handleHighlight(_ notification: Notification) { applyTextMarkup(.highlight, from: notification) }
        @objc func handleUnderline(_ notification: Notification) { applyTextMarkup(.underline, from: notification) }
        @objc func handleStrikethrough(_ notification: Notification) { applyTextMarkup(.strikeOut, from: notification) }

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

        @objc func handleApplySignature(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let image = notification.userInfo?["image"] as? NSImage else { return }
            pdfView.placeSignature(image: image)
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
    var isEditing: Bool = false

    init(bounds: CGRect, image: NSImage) {
        self.signatureImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        self.signatureImage = NSImage()
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.draw(cgImage, in: bounds)

        if isEditing {
            // Dashed selection border
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(bounds)

            // Corner handles
            let handleSize: CGFloat = 8
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)

            let corners = [
                CGPoint(x: bounds.minX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.minX, y: bounds.maxY),
                CGPoint(x: bounds.maxX, y: bounds.maxY),
            ]
            for corner in corners {
                let rect = CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            }
        }
    }
}
