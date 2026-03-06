import SwiftUI
import PDFKit

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

        // Navigate to page if changed externally (e.g. thumbnail click)
        if let page = document.page(at: currentPage),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        // Handle search
        context.coordinator.search(searchText, in: pdfView)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var lastSearchText = ""
        private var currentSelections: [PDFSelection] = []

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let pageIndex = pdfView.document?.index(for: currentPage) else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }

        func search(_ text: String, in pdfView: PDFView) {
            guard text != lastSearchText else { return }
            lastSearchText = text

            // Clear previous highlights
            pdfView.highlightedSelections = nil

            guard !text.isEmpty, let document = pdfView.document else { return }

            let selections = document.findString(text, withOptions: .caseInsensitive)
            if !selections.isEmpty {
                pdfView.highlightedSelections = selections
                // Go to first result
                if let first = selections.first {
                    pdfView.go(to: first)
                }
            }
        }
    }
}
