import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        loadDocument(into: pdfView, from: url)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            loadDocument(into: pdfView, from: url)
        }
    }

    private func loadDocument(into pdfView: PDFView, from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let document = PDFDocument(url: url)
            DispatchQueue.main.async {
                pdfView.document = document
            }
        }
    }
}
