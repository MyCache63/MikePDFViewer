import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var pdfURL: URL?
    @EnvironmentObject var recentFiles: RecentFilesManager
    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var searchText: String = ""
    @State private var showSearch = false
    @State private var showMergeSheet = false
    @State private var sidebarVisible = true

    var body: some View {
        NavigationSplitView {
            if let document = pdfDocument {
                ThumbnailSidebar(
                    document: document,
                    currentPage: $currentPage,
                    totalPages: totalPages
                )
            } else {
                VStack {
                    Text("No PDF Open")
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        } detail: {
            ZStack {
                if let document = pdfDocument {
                    PDFKitView(
                        document: document,
                        currentPage: $currentPage,
                        searchText: searchText
                    )
                } else {
                    emptyState
                }

                if showSearch, pdfDocument != nil {
                    searchBar
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 120, ideal: 160, max: 250)
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    openPDF()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open PDF (Cmd+O)")

                Button {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search (Cmd+F)")

                Button {
                    showMergeSheet = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Merge PDFs")

                if totalPages > 0 {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 100)
                }
            }
        }
        .onChange(of: pdfURL) { _, newURL in
            loadDocument(from: newURL)
        }
        .onAppear {
            loadDocument(from: pdfURL)
        }
        .sheet(isPresented: $showMergeSheet) {
            PDFMergeView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .background(KeyboardHandler(
            onFind: { showSearch.toggle(); if !showSearch { searchText = "" } },
            onEscape: { showSearch = false; searchText = "" }
        ))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No PDF Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Open PDF") {
                openPDF()
            }
            .buttonStyle(.borderedProminent)

            if !recentFiles.recentURLs.isEmpty {
                Divider().frame(width: 200)
                Text("Recent Files")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(recentFiles.recentURLs.prefix(5), id: \.self) { url in
                    Button(url.lastPathComponent) {
                        recentFiles.add(url)
                        pdfURL = url
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search in PDF...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showSearch = false
                        searchText = ""
                    } label: {
                        Text("Done")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(8)
                .shadow(radius: 4)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            recentFiles.add(url)
            pdfURL = url
        }
    }

    private func loadDocument(from url: URL?) {
        guard let url else {
            pdfDocument = nil
            totalPages = 0
            currentPage = 0
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let doc = PDFDocument(url: url)
            DispatchQueue.main.async {
                pdfDocument = doc
                totalPages = doc?.pageCount ?? 0
                currentPage = 0
            }
        }
    }
}

struct KeyboardHandler: NSViewRepresentable {
    let onFind: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onFind = onFind
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onFind = onFind
        nsView.onEscape = onEscape
    }
}

class KeyCatcherView: NSView {
    var onFind: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            onFind?()
        } else if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

#Preview {
    ContentView(pdfURL: .constant(nil))
        .environmentObject(RecentFilesManager())
}
