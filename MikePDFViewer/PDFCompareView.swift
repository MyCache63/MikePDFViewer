import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PDFCompareView: View {
    let document1: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var document2: PDFDocument?
    @State private var currentPage = 0
    @State private var result: PDFCompareResult?
    @State private var isComparing = false
    @State private var sensitivity: Double = 30
    @State private var viewMode: ViewMode = .sideBySide

    enum ViewMode: String, CaseIterable {
        case sideBySide = "Side by Side"
        case overlay = "Difference Overlay"
    }

    private var maxPages: Int {
        let count1 = document1.pageCount
        let count2 = document2?.pageCount ?? 0
        return max(count1, count2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if document2 != nil {
                comparisonContent
            } else {
                loadPrompt
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Text("Compare PDFs")
                .font(.headline)

            Spacer()

            if document2 != nil {
                Picker("View:", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                HStack {
                    Text("Sensitivity:")
                    Slider(value: $sensitivity, in: 5...100, step: 5)
                        .frame(width: 100)
                    Text("\(Int(sensitivity))")
                        .frame(width: 30)
                }

                Button("Re-compare") { comparePage() }
                    .disabled(isComparing)
            }

            Button("Done") { dismiss() }
        }
        .padding()
    }

    private var loadPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a second PDF to compare with")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Choose PDF...") { loadSecondPDF() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var comparisonContent: some View {
        VStack(spacing: 0) {
            if let result {
                comparisonImages(result)
            } else if isComparing {
                VStack {
                    Spacer()
                    ProgressView("Comparing pages...")
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a page to compare")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Page navigation
            HStack {
                Button("Previous") {
                    if currentPage > 0 {
                        currentPage -= 1
                        comparePage()
                    }
                }
                .disabled(currentPage == 0 || isComparing)

                Spacer()

                Text("Page \(currentPage + 1) of \(maxPages)")

                if let pct = result?.diffPercentage {
                    Text(String(format: "%.1f%% different", pct))
                        .foregroundStyle(pct > 5 ? .red : pct > 0.5 ? .orange : .green)
                        .fontWeight(.medium)
                }

                Spacer()

                Button("Next") {
                    if currentPage < maxPages - 1 {
                        currentPage += 1
                        comparePage()
                    }
                }
                .disabled(currentPage >= maxPages - 1 || isComparing)
            }
            .padding()
        }
        .onAppear { comparePage() }
    }

    @ViewBuilder
    private func comparisonImages(_ result: PDFCompareResult) -> some View {
        switch viewMode {
        case .sideBySide:
            HStack(spacing: 2) {
                VStack {
                    Text("Document 1").font(.caption).foregroundStyle(.secondary)
                    Image(nsImage: result.page1Image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                Divider()
                VStack {
                    Text("Document 2").font(.caption).foregroundStyle(.secondary)
                    Image(nsImage: result.page2Image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .padding()
        case .overlay:
            VStack {
                Text("Differences highlighted in red").font(.caption).foregroundStyle(.secondary)
                Image(nsImage: result.diffImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
        }
    }

    private func loadSecondPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            document2 = PDFDocument(url: url)
            if document2 != nil {
                comparePage()
            }
        }
    }

    private func comparePage() {
        guard let doc2 = document2,
              let page1 = document1.page(at: currentPage),
              let page2 = doc2.page(at: currentPage) else {
            result = nil
            return
        }

        isComparing = true
        result = nil
        let sens = CGFloat(sensitivity)

        DispatchQueue.global(qos: .userInitiated).async {
            let compareResult = PDFCompareService.comparePages(
                page1: page1,
                page2: page2,
                dpi: 150,
                sensitivity: sens
            )
            DispatchQueue.main.async {
                result = compareResult
                isComparing = false
            }
        }
    }
}
