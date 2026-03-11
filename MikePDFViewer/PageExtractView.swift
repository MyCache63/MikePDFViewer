import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PageExtractView: View {
    let document: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPages: Set<Int> = []
    @State private var selectAll = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pageGrid
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            selectedPages = Set(0..<document.pageCount)
        }
    }

    private var header: some View {
        HStack {
            Text("Extract Pages")
                .font(.headline)
            Spacer()
            Text("\(selectedPages.count) of \(document.pageCount) pages selected")
                .foregroundStyle(.secondary)
            Button(selectAll ? "Deselect All" : "Select All") {
                if selectAll {
                    selectedPages.removeAll()
                } else {
                    selectedPages = Set(0..<document.pageCount)
                }
                selectAll.toggle()
            }
        }
        .padding()
    }

    private var pageGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    PageThumbnailToggle(
                        document: document,
                        pageIndex: index,
                        isSelected: selectedPages.contains(index)
                    )
                    .onTapGesture {
                        if selectedPages.contains(index) {
                            selectedPages.remove(index)
                        } else {
                            selectedPages.insert(index)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Extract \(selectedPages.count) Pages") {
                extractPages()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPages.isEmpty)
        }
        .padding()
    }

    private func extractPages() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Extracted Pages.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let newDoc = PDFDocument()
        let sortedPages = selectedPages.sorted()
        for (insertIndex, pageIndex) in sortedPages.enumerated() {
            if let page = document.page(at: pageIndex) {
                newDoc.insert(page, at: insertIndex)
            }
        }
        newDoc.write(to: url)
        dismiss()
    }
}

struct PageThumbnailToggle: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(8.5/11, contentMode: .fit)
                }
            }
            .frame(height: 120)
            .background(Color.white)
            .cornerRadius(4)
            .shadow(radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
            )
            .opacity(isSelected ? 1.0 : 0.5)

            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.caption)
                Text("\(pageIndex + 1)")
                    .font(.caption2)
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                guard let page = document.page(at: pageIndex) else { return }
                let img = page.thumbnail(of: CGSize(width: 100, height: 140), for: .mediaBox)
                DispatchQueue.main.async { thumbnail = img }
            }
        }
    }
}
