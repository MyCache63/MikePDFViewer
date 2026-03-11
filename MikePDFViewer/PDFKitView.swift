import SwiftUI
import PDFKit

extension Notification.Name {
    static let pdfZoomIn = Notification.Name("pdfZoomIn")
    static let pdfZoomOut = Notification.Name("pdfZoomOut")
    static let pdfZoomFit = Notification.Name("pdfZoomFit")
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let searchText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document

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

        context.coordinator.search(searchText, in: pdfView)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var lastSearchText = ""

        init(_ parent: PDFKitView) {
            self.parent = parent
            super.init()

            NotificationCenter.default.addObserver(self, selector: #selector(handleZoomIn), name: .pdfZoomIn, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleZoomOut), name: .pdfZoomOut, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleZoomFit), name: .pdfZoomFit, object: nil)
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
