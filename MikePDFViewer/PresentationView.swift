import SwiftUI
import PDFKit

struct PresentationView: View {
    let document: PDFDocument
    let startPage: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PresentationPDFView(document: document, currentPage: $currentPage)

            // Page indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(currentPage + 1) / \(document.pageCount)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(6)
                        .padding()
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                Spacer()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            currentPage = startPage
        }
    }
}

struct PresentationPDFView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = .black

        if let page = document.page(at: currentPage) {
            pdfView.go(to: page)
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView

        // Add keyboard monitor for arrow navigation
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return context.coordinator.handleKeyDown(event) ? nil : event
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let page = document.page(at: currentPage),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
    }

    class Coordinator: NSObject {
        var parent: PresentationPDFView
        weak var pdfView: PDFView?

        init(_ parent: PresentationPDFView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let current = pdfView.currentPage,
                  let index = pdfView.document?.index(for: current) else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = index
            }
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let pdfView = pdfView else { return false }
            switch event.keyCode {
            case 124, 125: // Right arrow, Down arrow
                if pdfView.canGoToNextPage {
                    pdfView.goToNextPage(nil)
                    return true
                }
            case 123, 126: // Left arrow, Up arrow
                if pdfView.canGoToPreviousPage {
                    pdfView.goToPreviousPage(nil)
                    return true
                }
            case 49: // Space bar
                if pdfView.canGoToNextPage {
                    pdfView.goToNextPage(nil)
                    return true
                }
            default:
                break
            }
            return false
        }
    }
}
