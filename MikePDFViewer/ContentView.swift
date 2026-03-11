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
    @State private var showOCRSheet = false
    @State private var showGoToPage = false
    @State private var goToPageText: String = ""
    @State private var darkModeReading = false
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var documentVersion: Int = 0

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationSplitView {
            if let document = pdfDocument {
                ThumbnailSidebar(
                    document: document,
                    currentPage: $currentPage,
                    totalPages: totalPages,
                    documentVersion: documentVersion
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
                        searchText: searchText,
                        darkMode: darkModeReading,
                        displayMode: displayMode
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
        .navigationTitle(pdfURL?.lastPathComponent ?? "MikePDFViewer")
        .navigationSubtitle("v\(appVersion)")
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // File group
                Button {
                    openPDF()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open PDF (Cmd+O)")

                Button {
                    saveDocumentAs()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save As (Shift+Cmd+S)")
                .disabled(pdfDocument == nil)

                Button {
                    printDocument()
                } label: {
                    Image(systemName: "printer")
                }
                .help("Print (Cmd+P)")
                .disabled(pdfDocument == nil)

                if let url = pdfURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share PDF")
                }

                Divider()

                // Search
                Button {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search (Cmd+F)")

                Divider()

                // Zoom
                Button {
                    NotificationCenter.default.post(name: .pdfZoomOut, object: nil)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out (Cmd+-)")
                .disabled(pdfDocument == nil)

                Button {
                    NotificationCenter.default.post(name: .pdfZoomIn, object: nil)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In (Cmd++)")
                .disabled(pdfDocument == nil)

                Divider()

                // View controls
                Button {
                    darkModeReading.toggle()
                } label: {
                    Image(systemName: darkModeReading ? "sun.max" : "moon")
                }
                .help(darkModeReading ? "Light Mode" : "Dark Reading Mode")
                .disabled(pdfDocument == nil)

                Button {
                    NotificationCenter.default.post(name: .pdfRotateLeft, object: nil)
                } label: {
                    Image(systemName: "rotate.left")
                }
                .help("Rotate Left")
                .disabled(pdfDocument == nil)

                Button {
                    NotificationCenter.default.post(name: .pdfRotateRight, object: nil)
                } label: {
                    Image(systemName: "rotate.right")
                }
                .help("Rotate Right")
                .disabled(pdfDocument == nil)

                Picker("", selection: $displayMode) {
                    Text("Continuous").tag(PDFDisplayMode.singlePageContinuous)
                    Text("Single Page").tag(PDFDisplayMode.singlePage)
                    Text("Two Pages").tag(PDFDisplayMode.twoUp)
                    Text("Two Pages Scroll").tag(PDFDisplayMode.twoUpContinuous)
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .help("Display Mode")
                .disabled(pdfDocument == nil)

                Divider()

                // Tools
                Button {
                    showOCRSheet = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("OCR Document")
                .disabled(pdfDocument == nil)

                Button {
                    showMergeSheet = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Merge PDFs")

                // Page indicator
                if totalPages > 0 {
                    Button {
                        goToPageText = ""
                        showGoToPage = true
                    } label: {
                        Text("Page \(currentPage + 1) of \(totalPages)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Go to Page (Cmd+G)")
                    .popover(isPresented: $showGoToPage) {
                        goToPagePopover
                    }
                }

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
        }
        .focusedSceneValue(\.pdfDocument, pdfDocument)
        .focusedSceneValue(\.pdfFileURL, pdfURL)
        .focusedSceneValue(\.isDarkMode, darkModeReading)
        .focusedSceneValue(\.displayModeRawValue, displayMode.rawValue)
        .onReceive(NotificationCenter.default.publisher(for: .pdfDocumentModified)) { _ in
            documentVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfToggleDarkMode)) { _ in
            darkModeReading.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pdfSetDisplayMode)) { notification in
            if let rawValue = notification.userInfo?["mode"] as? Int,
               let mode = PDFDisplayMode(rawValue: rawValue) {
                displayMode = mode
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
        .sheet(isPresented: $showOCRSheet) {
            if let document = pdfDocument {
                OCRView(document: document)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .background(KeyboardHandler(
            onFind: { showSearch.toggle(); if !showSearch { searchText = "" } },
            onEscape: { showSearch = false; searchText = "" },
            onOCR: { if pdfDocument != nil { showOCRSheet = true } },
            onGoToPage: { if totalPages > 0 { goToPageText = ""; showGoToPage = true } }
        ))
    }

    // MARK: - Go to Page

    private var goToPagePopover: some View {
        VStack(spacing: 12) {
            Text("Go to Page")
                .font(.headline)
            HStack {
                TextField("Page number", text: $goToPageText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { navigateToPage() }
                Text("of \(totalPages)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { showGoToPage = false }
                    .keyboardShortcut(.cancelAction)
                Button("Go") { navigateToPage() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(goToPageText) == nil)
            }
        }
        .padding()
    }

    private func navigateToPage() {
        guard let pageNum = Int(goToPageText),
              pageNum >= 1, pageNum <= totalPages else { return }
        currentPage = pageNum - 1
        showGoToPage = false
    }

    // MARK: - Empty State

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

    // MARK: - Search Bar

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

    // MARK: - Actions

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            recentFiles.add(url)
            pdfURL = url
        }
    }

    private func saveDocumentAs() {
        guard let document = pdfDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = pdfURL?.lastPathComponent ?? "Untitled.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            document.write(to: url)
        }
    }

    private func printDocument() {
        guard let document = pdfDocument else { return }
        let printInfo = NSPrintInfo.shared
        if let printOperation = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) {
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true
            printOperation.run()
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
                documentVersion = 0
            }
        }
    }
}

// MARK: - Keyboard Handler

struct KeyboardHandler: NSViewRepresentable {
    let onFind: () -> Void
    let onEscape: () -> Void
    let onOCR: () -> Void
    let onGoToPage: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onFind = onFind
        view.onEscape = onEscape
        view.onOCR = onOCR
        view.onGoToPage = onGoToPage
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onFind = onFind
        nsView.onEscape = onEscape
        nsView.onOCR = onOCR
        nsView.onGoToPage = onGoToPage
    }
}

class KeyCatcherView: NSView {
    var onFind: (() -> Void)?
    var onEscape: (() -> Void)?
    var onOCR: (() -> Void)?
    var onGoToPage: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command] && event.charactersIgnoringModifiers == "f" {
            onFind?()
        } else if mods == [.command, .shift] && event.charactersIgnoringModifiers == "R" {
            onOCR?()
        } else if mods == [.command] && event.charactersIgnoringModifiers == "g" {
            onGoToPage?()
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
