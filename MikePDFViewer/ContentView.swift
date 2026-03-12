import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State var pdfURL: URL?
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
    @State private var showAnnotationBar = false
    @State private var annotationColor: Color = .yellow
    @State private var formFieldCount: Int = 0
    @State private var showExtractSheet = false
    @State private var showSplitView = false
    @State private var splitCurrentPage: Int = 0
    @State private var showPresentation = false
    @State private var showSignatureSheet = false
    @State private var showRedactConfirm = false
    @State private var showPasswordSheet = false
    @State private var showEncryptSheet = false
    @State private var showWatermarkSheet = false
    @State private var showExportImages = false
    @State private var showCompareSheet = false
    @State private var pendingSignatureImage: NSImage?
    @State private var annotationEditingMode = false
    @State private var editingAnnotationType = ""
    @State private var editingAnnotationText = ""
    @StateObject private var bookmarkManager = BookmarkManager()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        viewWithNotifications
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
            .sheet(isPresented: $showExtractSheet) {
                if let document = pdfDocument {
                    PageExtractView(document: document)
                        .frame(minWidth: 700, minHeight: 500)
                }
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureView { image in
                    pendingSignatureImage = image
                }
            }
            .onChange(of: showSignatureSheet) { _, isShowing in
                if !isShowing, let image = pendingSignatureImage {
                    pendingSignatureImage = nil
                    NotificationCenter.default.post(
                        name: .pdfApplySignature,
                        object: nil,
                        userInfo: ["image": image]
                    )
                }
            }
            .sheet(isPresented: $showPasswordSheet) {
                if let document = pdfDocument {
                    PasswordSheet(document: document, onUnlock: {
                        documentVersion += 1
                        totalPages = document.pageCount
                    })
                }
            }
            .sheet(isPresented: $showEncryptSheet) {
                if let document = pdfDocument {
                    EncryptSheet(document: document, currentURL: pdfURL)
                }
            }
            .sheet(isPresented: $showWatermarkSheet) {
                if let document = pdfDocument {
                    WatermarkSheet(document: document)
                }
            }
            .sheet(isPresented: $showExportImages) {
                if let document = pdfDocument {
                    ExportImagesView(document: document)
                }
            }
            .sheet(isPresented: $showCompareSheet) {
                if let document = pdfDocument {
                    PDFCompareView(document1: document)
                }
            }
            .background(KeyboardHandler(
                onFind: { showSearch.toggle(); if !showSearch { searchText = "" } },
                onEscape: { showSearch = false; searchText = "" },
                onOCR: { if pdfDocument != nil { showOCRSheet = true } },
                onGoToPage: { if totalPages > 0 { goToPageText = ""; showGoToPage = true } }
            ))
    }

    private var viewWithNotifications: some View {
        viewWithAlerts
            .onReceive(NotificationCenter.default.publisher(for: .pdfDocumentModified)) { _ in
                documentVersion += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfAnnotationEditingChanged)) { notification in
                annotationEditingMode = notification.userInfo?["editing"] as? Bool ?? false
                editingAnnotationType = notification.userInfo?["type"] as? String ?? ""
                if annotationEditingMode {
                    editingAnnotationText = notification.userInfo?["text"] as? String ?? ""
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .pdfToggleBookmark)) { _ in
                if pdfDocument != nil { bookmarkManager.toggleBookmark(for: currentPage) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfExtractPages)) { _ in
                if pdfDocument != nil { showExtractSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfShowMerge)) { _ in
                showMergeSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfOpenFile)) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    recentFiles.add(url)
                    pdfURL = url
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfToggleSplitView)) { _ in
                if pdfDocument != nil {
                    showSplitView.toggle()
                    if showSplitView { splitCurrentPage = currentPage }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfStartPresentation)) { _ in
                if pdfDocument != nil { showPresentation = true }
            }
            .onChange(of: pdfURL) { _, newURL in loadDocument(from: newURL) }
            .onAppear { loadDocument(from: pdfURL) }
            .onOpenURL { url in recentFiles.add(url); pdfURL = url }
    }

    private var viewWithAlerts: some View {
        mainView
            .focusedSceneValue(\.pdfDocument, pdfDocument)
            .focusedSceneValue(\.pdfFileURL, pdfURL)
            .focusedSceneValue(\.isDarkMode, darkModeReading)
            .focusedSceneValue(\.displayModeRawValue, displayMode.rawValue)
            .alert("Redact Selected Text", isPresented: $showRedactConfirm) {
                Button("Redact", role: .destructive) {
                    NotificationCenter.default.post(name: .pdfRedactSelection, object: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the selected text by flattening affected pages to images. This cannot be undone.")
            }
    }

    // MARK: - Main Layout

    private var mainView: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewColumnWidth(min: 120, ideal: 160, max: 250)
        .navigationTitle(pdfURL?.lastPathComponent ?? "MikePDFViewer")
        .navigationSubtitle("v\(appVersion)")
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                fileToolbar
            }
            ToolbarItemGroup(placement: .automatic) {
                viewToolbar
            }
            ToolbarItemGroup(placement: .automatic) {
                toolsToolbar
            }
            ToolbarItemGroup(placement: .automatic) {
                statusToolbar
            }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if let document = pdfDocument {
            ThumbnailSidebar(
                document: document,
                currentPage: $currentPage,
                totalPages: totalPages,
                documentVersion: documentVersion,
                bookmarkManager: bookmarkManager,
                onMovePage: { from, to in
                    movePage(from: from, to: to)
                },
                onDeletePages: { pageIndices in
                    deletePages(pageIndices)
                }
            )
        } else {
            VStack {
                Text("No PDF Open")
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            annotationBar
            if showSplitView, let document = pdfDocument {
                HSplitView {
                    pdfContent
                    PDFKitView(
                        document: document,
                        currentPage: $splitCurrentPage,
                        searchText: "",
                        darkMode: darkModeReading,
                        displayMode: displayMode
                    )
                }
            } else {
                pdfContent
            }
        }
        .sheet(isPresented: $showPresentation) {
            if let document = pdfDocument {
                PresentationView(document: document, startPage: currentPage)
            }
        }
    }

    @ViewBuilder
    private var annotationBar: some View {
        if showAnnotationBar, pdfDocument != nil {
            AnnotationToolbar(
                annotationColor: $annotationColor,
                onHighlight: { applyMarkup(.pdfApplyHighlight) },
                onUnderline: { applyMarkup(.pdfApplyUnderline) },
                onStrikethrough: { applyMarkup(.pdfApplyStrikethrough) },
                onAddNote: { PrintablePDFView.current?.placeStickyNote(color: NSColor(annotationColor)) },
                onAddText: { PrintablePDFView.current?.placeFreeText() },
                onDone: { showAnnotationBar = false }
            )
        }
    }

    private var pdfContent: some View {
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

            if annotationEditingMode {
                VStack {
                    annotationEditingBanner
                    Spacer()
                }
            }
        }
    }

    // MARK: - Toolbar Groups

    @ViewBuilder
    private var fileToolbar: some View {
        Button { openPDF() } label: { Image(systemName: "folder") }
            .help("Open PDF (Cmd+O)")

        Button { saveDocumentAs() } label: { Image(systemName: "square.and.arrow.down") }
            .help("Save As (Shift+Cmd+S)")
            .disabled(pdfDocument == nil)

        Button { PrintablePDFView.current?.performPrint() } label: { Image(systemName: "printer") }
            .help("Print (Cmd+P)")
            .disabled(pdfDocument == nil)

        if let url = pdfURL {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                .help("Share PDF")
        }

        Divider()

        Button {
            showSearch.toggle()
            if !showSearch { searchText = "" }
        } label: { Image(systemName: "magnifyingglass") }
            .help("Search (Cmd+F)")
    }

    @ViewBuilder
    private var viewToolbar: some View {
        Button { NotificationCenter.default.post(name: .pdfZoomOut, object: nil) } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .help("Zoom Out").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfZoomIn, object: nil) } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .help("Zoom In").disabled(pdfDocument == nil)

        Button { darkModeReading.toggle() } label: {
            Image(systemName: darkModeReading ? "sun.max" : "moon")
        }
        .help(darkModeReading ? "Light Mode" : "Dark Reading Mode").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfRotateLeft, object: nil) } label: {
            Image(systemName: "rotate.left")
        }
        .help("Rotate Left").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfRotateRight, object: nil) } label: {
            Image(systemName: "rotate.right")
        }
        .help("Rotate Right").disabled(pdfDocument == nil)

        Picker("", selection: $displayMode) {
            Text("Continuous").tag(PDFDisplayMode.singlePageContinuous)
            Text("Single Page").tag(PDFDisplayMode.singlePage)
            Text("Two Pages").tag(PDFDisplayMode.twoUp)
            Text("Two Pages Scroll").tag(PDFDisplayMode.twoUpContinuous)
        }
        .pickerStyle(.menu).frame(width: 130)
        .help("Display Mode").disabled(pdfDocument == nil)

        Button { showSplitView.toggle(); if showSplitView { splitCurrentPage = currentPage } } label: {
            Image(systemName: showSplitView ? "rectangle" : "rectangle.split.2x1")
        }
        .help(showSplitView ? "Close Split View" : "Split View").disabled(pdfDocument == nil)

        Button { showPresentation = true } label: {
            Image(systemName: "play.rectangle")
        }
        .help("Presentation Mode").disabled(pdfDocument == nil)
    }

    @ViewBuilder
    private var toolsToolbar: some View {
        Button { showAnnotationBar.toggle() } label: {
            Image(systemName: "pencil.tip.crop.circle")
        }
        .help("Markup Tools").disabled(pdfDocument == nil)

        Button { bookmarkManager.toggleBookmark(for: currentPage) } label: {
            Image(systemName: bookmarkManager.isBookmarked(currentPage) ? "bookmark.fill" : "bookmark")
        }
        .help("Toggle Bookmark (Cmd+D)").disabled(pdfDocument == nil)

        Button { showExtractSheet = true } label: {
            Image(systemName: "doc.badge.plus")
        }
        .help("Extract Pages").disabled(pdfDocument == nil)

        Button { showSignatureSheet = true } label: {
            Image(systemName: "signature")
        }
        .help("Add Signature").disabled(pdfDocument == nil)

        Button {
            showRedactConfirm = true
        } label: {
            Image(systemName: "eye.slash")
        }
        .help("Redact Selection (select text first)").disabled(pdfDocument == nil)

        Button { showOCRSheet = true } label: {
            Image(systemName: "doc.text.magnifyingglass")
        }
        .help("OCR Document").disabled(pdfDocument == nil)

        Button { showEncryptSheet = true } label: {
            Image(systemName: "lock.shield")
        }
        .help("Password Protect").disabled(pdfDocument == nil)

        Button { showWatermarkSheet = true } label: {
            Image(systemName: "drop.triangle")
        }
        .help("Add Watermark").disabled(pdfDocument == nil)

        Button { showExportImages = true } label: {
            Image(systemName: "photo.on.rectangle")
        }
        .help("Export as Images").disabled(pdfDocument == nil)

        Button { showCompareSheet = true } label: {
            Image(systemName: "square.split.2x1")
        }
        .help("Compare PDFs").disabled(pdfDocument == nil)

        Button { showMergeSheet = true } label: {
            Image(systemName: "doc.on.doc")
        }
        .help("Merge PDFs")
    }

    @ViewBuilder
    private var statusToolbar: some View {
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

        if formFieldCount > 0 {
            Label("\(formFieldCount) fields", systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.caption2)
                .foregroundStyle(.orange)
        }

        Text("v\(appVersion)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
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

    // MARK: - Annotation Editing Banner

    private var annotationEditingBanner: some View {
        HStack(spacing: 12) {
            if editingAnnotationType == "stickyNote" || editingAnnotationType == "freeText" {
                Image(systemName: editingAnnotationType == "stickyNote" ? "note.text" : "textbox")
                TextField("Type text here...", text: $editingAnnotationText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: editingAnnotationText) { _, newText in
                        PrintablePDFView.current?.updateActiveAnnotationText(newText)
                    }
            } else {
                Image(systemName: "signature")
            }

            if editingAnnotationType == "stickyNote" {
                Text("Drag to move")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Drag to move, drag corners to resize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Done") {
                PrintablePDFView.current?.finalizeAnnotation()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Delete") {
                PrintablePDFView.current?.cancelAnnotation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.top, 8)
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
            Button("Open PDF") { openPDF() }
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
                        Text("Done").font(.caption)
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

    private func applyMarkup(_ notificationName: Notification.Name) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["color": NSColor(annotationColor)]
        )
    }


    private func deletePages(_ pageIndices: [Int]) {
        guard let document = pdfDocument else { return }
        // pageIndices should be sorted descending so removal doesn't shift indices
        for index in pageIndices {
            guard index >= 0, index < document.pageCount, document.pageCount > 1 else { continue }
            document.removePage(at: index)
        }
        totalPages = document.pageCount
        if currentPage >= totalPages {
            currentPage = max(0, totalPages - 1)
        }
        documentVersion += 1
        NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
    }

    private func movePage(from source: Int, to destination: Int) {
        guard let document = pdfDocument,
              source != destination,
              source >= 0, source < document.pageCount,
              destination >= 0, destination < document.pageCount,
              let page = document.page(at: source) else { return }

        document.removePage(at: source)
        document.insert(page, at: destination)
        documentVersion += 1

        // Update current page to follow the moved page
        if currentPage == source {
            currentPage = destination
        } else if source < destination && currentPage > source && currentPage <= destination {
            currentPage -= 1
        } else if source > destination && currentPage >= destination && currentPage < source {
            currentPage += 1
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
            let isLocked = doc?.isLocked ?? false
            let fields = isLocked ? 0 : Self.countFormFields(doc)
            DispatchQueue.main.async {
                pdfDocument = doc
                totalPages = isLocked ? 0 : (doc?.pageCount ?? 0)
                currentPage = 0
                documentVersion = 0
                formFieldCount = fields
                bookmarkManager.load(for: url)
                if isLocked {
                    showPasswordSheet = true
                }
            }
        }
    }

    private static func countFormFields(_ document: PDFDocument?) -> Int {
        guard let document else { return 0 }
        var count = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations {
                if annotation.type == "Widget" {
                    count += 1
                }
            }
        }
        return count
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
    ContentView()
        .environmentObject(RecentFilesManager())
}
