import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PDFMergeView: View {
    @State private var sourceFiles: [MergeSource] = []
    @State private var isDragOver = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Merge PDFs")
                    .font(.title2.bold())
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    Button("Add PDFs...") {
                        addPDFs()
                    }
                    Button("Merge & Save") {
                        mergeAndSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sourceFiles.isEmpty)
                }
            }
            .padding()

            Divider()

            if sourceFiles.isEmpty {
                dropZone
            } else {
                fileList
            }
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 50))
                .foregroundStyle(isDragOver ? Color.blue : Color.secondary)
            Text("Drop PDF files here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("or click \"Add PDFs\" above")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragOver ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding()
        )
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(sourceFiles.enumerated()), id: \.element.id) { fileIndex, source in
                    MergeSourceCard(
                        source: $sourceFiles[fileIndex],
                        onRemove: { sourceFiles.remove(at: fileIndex) },
                        onMoveUp: fileIndex > 0 ? {
                            sourceFiles.swapAt(fileIndex, fileIndex - 1)
                        } : nil,
                        onMoveDown: fileIndex < sourceFiles.count - 1 ? {
                            sourceFiles.swapAt(fileIndex, fileIndex + 1)
                        } : nil
                    )
                }
            }
            .padding()
        }
    }

    private func addPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let doc = PDFDocument(url: url) {
                    let pages = (0..<doc.pageCount).map { PageItem(pageIndex: $0, included: true) }
                    sourceFiles.append(MergeSource(
                        url: url,
                        document: doc,
                        pages: pages
                    ))
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                DispatchQueue.main.async {
                    if let doc = PDFDocument(url: url) {
                        let pages = (0..<doc.pageCount).map { PageItem(pageIndex: $0, included: true) }
                        sourceFiles.append(MergeSource(
                            url: url,
                            document: doc,
                            pages: pages
                        ))
                    }
                }
            }
        }
    }

    private func mergeAndSave() {
        let merged = PDFDocument()
        var insertIndex = 0

        for source in sourceFiles {
            for pageItem in source.pages where pageItem.included {
                if let page = source.document.page(at: pageItem.pageIndex) {
                    merged.insert(page, at: insertIndex)
                    insertIndex += 1
                }
            }
        }

        guard merged.pageCount > 0 else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Merged.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            merged.write(to: url)
        }
    }
}

struct MergeSource: Identifiable {
    let id = UUID()
    let url: URL
    let document: PDFDocument
    var pages: [PageItem]
}

struct PageItem: Identifiable {
    let id = UUID()
    let pageIndex: Int
    var included: Bool
}

struct MergeSourceCard: View {
    @Binding var source: MergeSource
    let onRemove: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var expanded = false

    var includedCount: Int {
        source.pages.filter(\.included).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text(source.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(includedCount) of \(source.pages.count) pages selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    if let onMoveUp {
                        Button { onMoveUp() } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                    }
                    if let onMoveDown {
                        Button { onMoveDown() } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up.circle" : "chevron.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show/hide pages")

                    Button { onRemove() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(12)

            // Page grid (expandable)
            if expanded {
                Divider()
                HStack(spacing: 8) {
                    Button("Select All") {
                        for i in source.pages.indices {
                            source.pages[i].included = true
                        }
                    }
                    .font(.caption)
                    Button("Deselect All") {
                        for i in source.pages.indices {
                            source.pages[i].included = false
                        }
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(source.pages.enumerated()), id: \.element.id) { index, pageItem in
                        MergePageThumbnail(
                            document: source.document,
                            pageItem: pageItem,
                            onToggle: {
                                source.pages[index].included.toggle()
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}

struct MergePageThumbnail: View {
    let document: PDFDocument
    let pageItem: PageItem
    let onToggle: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(8.5/11, contentMode: .fit)
                }

                if !pageItem.included {
                    Color.black.opacity(0.5)
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(pageItem.included ? Color.accentColor : Color.red, lineWidth: pageItem.included ? 0 : 2)
            )
            .onTapGesture { onToggle() }

            Text("\(pageItem.pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(pageItem.included ? .primary : .secondary)
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        DispatchQueue.global(qos: .utility).async {
            guard let page = document.page(at: pageItem.pageIndex) else { return }
            let img = page.thumbnail(of: CGSize(width: 80, height: 110), for: .mediaBox)
            DispatchQueue.main.async {
                thumbnail = img
            }
        }
    }
}
