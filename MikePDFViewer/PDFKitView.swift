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
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let searchText: String
    let darkMode: Bool
    let displayMode: PDFDisplayMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
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

    func updateNSView(_ pdfView: PDFView, context: Context) {
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
        weak var pdfView: PDFView?
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
