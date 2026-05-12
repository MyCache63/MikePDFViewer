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
    @State private var editingFontSize: CGFloat = 14
    @State private var editingFontBold = false
    @State private var editingFontItalic = false
    @State private var editingFontName = "Helvetica"
    @State private var emlAttachments: [EMLAttachment] = []
    @State private var emlMessage: EMLMessage?
    @State private var isViewingEML: Bool = false
    @State private var originalEMLURL: URL?
    @State private var loadExternalImages: Bool = false
    @State private var emlConversionError: String?
    @State private var isConvertingEML: Bool = false
    @State private var isViewingDOCX: Bool = false
    @State private var originalDOCXURL: URL?
    @State private var docxTempPDFURL: URL?
    @State private var docxConversionError: String?
    @State private var isConvertingDOCX: Bool = false
    @State private var markdownDocument: MarkdownDocument?
    @State private var markdownAttributed: NSAttributedString?
    @State private var markdownAnchors: [String: NSRange] = [:]
    @State private var isViewingMarkdown: Bool = false
    @State private var originalMarkdownURL: URL?
    @State private var markdownMode: MarkdownMode = .reader
    @AppStorage("markdown-theme") private var markdownThemeRaw: String = MarkdownReaderTheme.github.rawValue
    @AppStorage("markdown-font-family") private var mdFontFamilyRaw: String = MarkdownTypography.FontFamily.system.rawValue
    @AppStorage("markdown-font-size") private var mdFontSize: Int = 16
    @AppStorage("markdown-line-height") private var mdLineHeight: Double = 1.6
    @AppStorage("markdown-content-width") private var mdContentWidthRaw: String = MarkdownTypography.ContentWidth.standard.rawValue
    @AppStorage("markdown-para-spacing") private var mdParaSpacingRaw: String = MarkdownTypography.ParagraphSpacing.normal.rawValue
    @AppStorage("markdown-focus-mode") private var mdFocusMode: Bool = false
    @State private var showMarkdownSettings: Bool = false
    @State private var markdownTOC: [MarkdownToHTML.TOCEntry] = []
    @State private var markdownStats: ReadingStats = .empty
    @State private var pendingMDAnchor: String? = nil
    @AppStorage("markdown-toc-visible") private var mdTOCVisible: Bool = true
    @StateObject private var mdSearch = MarkdownSearchController()

    private var markdownTheme: MarkdownReaderTheme {
        MarkdownReaderTheme(rawValue: markdownThemeRaw) ?? .github
    }
    private var markdownTypographyBinding: Binding<MarkdownTypography> {
        Binding(
            get: {
                MarkdownTypography(
                    fontFamily: MarkdownTypography.FontFamily(rawValue: mdFontFamilyRaw) ?? .system,
                    fontSize: mdFontSize,
                    lineHeight: mdLineHeight,
                    contentWidth: MarkdownTypography.ContentWidth(rawValue: mdContentWidthRaw) ?? .standard,
                    paragraphSpacing: MarkdownTypography.ParagraphSpacing(rawValue: mdParaSpacingRaw) ?? .normal
                )
            },
            set: { newValue in
                mdFontFamilyRaw = newValue.fontFamily.rawValue
                mdFontSize = newValue.fontSize
                mdLineHeight = newValue.lineHeight
                mdContentWidthRaw = newValue.contentWidth.rawValue
                mdParaSpacingRaw = newValue.paragraphSpacing.rawValue
            }
        )
    }
    private var markdownTypography: MarkdownTypography { markdownTypographyBinding.wrappedValue }
    @State private var isRenderingMarkdownPDF: Bool = false
    @State private var renderedPDFTempURL: URL?
    @State private var pendingRenderedSourceURL: URL?
    @State private var showSaveRenderedPDFPrompt: Bool = false
    @StateObject private var bookmarkManager = BookmarkManager()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// URL to use for "Open With" actions — always the user-facing source, not a
    /// rendered tmp PDF. Falls back through markdown → docx → eml → pdfURL.
    private var openWithSourceURL: URL? {
        if let url = originalMarkdownURL { return url }
        if let url = originalDOCXURL { return url }
        if let url = originalEMLURL { return url }
        return pdfURL
    }

    private var openWithFileKind: OpenWithFileKind {
        guard let url = openWithSourceURL else { return .other }
        return OpenWithFileKind.detect(url: url)
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
                    if let font = notification.userInfo?["font"] as? NSFont {
                        editingFontSize = font.pointSize
                        let td = NSFontTraitMask(rawValue: UInt(NSFontManager.shared.traits(of: font).rawValue))
                        editingFontBold = td.contains(.boldFontMask)
                        editingFontItalic = td.contains(.italicFontMask)
                        editingFontName = font.familyName ?? "Helvetica"
                    } else {
                        editingFontSize = 14
                        editingFontBold = false
                        editingFontItalic = false
                        editingFontName = "Helvetica"
                    }
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
            .alert("Save Rendered PDF?", isPresented: $showSaveRenderedPDFPrompt) {
                Button("Save…") { confirmSaveRenderedPDF() }
                Button("Keep in Temp", role: .cancel) {}
            } message: {
                Text("The PDF was rendered to a temporary file. Save it permanently to a folder of your choice, or leave it in the temp folder (auto-deleted after 7 days).")
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
        } else if isViewingMarkdown {
            if markdownMode == .reader && mdTOCVisible {
                MarkdownTOCSidebar(
                    entries: markdownTOC,
                    stats: markdownStats,
                    onJump: { slug in pendingMDAnchor = slug }
                )
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(markdownStats.readingTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(markdownStats.wordCount) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let url = originalMarkdownURL {
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                    }
                }
                .frame(maxHeight: .infinity)
            }
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
                    pdfContentWithEMLSidebar
                    PDFKitView(
                        document: document,
                        currentPage: $splitCurrentPage,
                        searchText: "",
                        darkMode: darkModeReading,
                        displayMode: displayMode
                    )
                }
            } else {
                pdfContentWithEMLSidebar
            }
        }
        .sheet(isPresented: $showPresentation) {
            if let document = pdfDocument {
                PresentationView(document: document, startPage: currentPage)
            }
        }
    }

    @ViewBuilder
    private var pdfContentWithEMLSidebar: some View {
        if isViewingMarkdown, let doc = markdownDocument {
            switch markdownMode {
            case .reader:
                MarkdownReaderView(source: doc.source,
                                   baseURL: originalMarkdownURL,
                                   theme: markdownTheme,
                                   typography: markdownTypography,
                                   focusMode: mdFocusMode,
                                   pendingScrollAnchor: $pendingMDAnchor,
                                   searchController: mdSearch)
            case .quick:
                if let attr = markdownAttributed {
                    MarkdownView(attributedString: attr,
                                 anchors: markdownAnchors,
                                 liveSearchText: $searchText)
                } else {
                    Text("Loading…").foregroundStyle(.secondary)
                }
            }
        } else if isViewingEML {
            HStack(spacing: 0) {
                pdfContent
                Divider()
                AttachmentsSidebar(
                    attachments: emlAttachments,
                    loadExternalImages: $loadExternalImages,
                    onReloadWithImages: { reloadEML() }
                )
            }
        } else {
            pdfContent
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

            if showSearch, (pdfDocument != nil || isViewingMarkdown) {
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

        OpenWithMenu(fileURL: openWithSourceURL, fileKind: openWithFileKind)

        if isViewingMarkdown {
            Button {
                markdownMode = (markdownMode == .reader) ? .quick : .reader
            } label: {
                Image(systemName: markdownMode == .reader ? "book" : "doc.plaintext")
            }
            .help(markdownMode == .reader ? "Switch to Quick view" : "Switch to Reader view")

            if markdownMode == .reader {
                Menu {
                    ForEach(MarkdownReaderTheme.allCases) { theme in
                        Button {
                            markdownThemeRaw = theme.rawValue
                        } label: {
                            HStack {
                                Text(theme.displayName)
                                if theme == markdownTheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .help("Reading Theme — \(markdownTheme.displayName)")

                Button { showMarkdownSettings.toggle() } label: {
                    Image(systemName: "textformat.size")
                }
                .help("Typography & Focus Mode")
                .popover(isPresented: $showMarkdownSettings, arrowEdge: .bottom) {
                    MarkdownReaderSettings(
                        typography: markdownTypographyBinding,
                        focusMode: $mdFocusMode
                    )
                }

                Button { mdTOCVisible.toggle() } label: {
                    Image(systemName: mdTOCVisible ? "list.bullet.indent" : "list.bullet")
                }
                .help(mdTOCVisible ? "Hide Table of Contents" : "Show Table of Contents")
            }

            Button { renderMarkdownAsPDF() } label: {
                if isRenderingMarkdownPDF {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "doc.richtext")
                }
            }
            .help("Render as PDF")
            .disabled(isRenderingMarkdownPDF)
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
        VStack(spacing: 6) {
            // Row 1: Text field (for text types) + action buttons
            HStack(spacing: 10) {
                if editingAnnotationType == "stickyNote" || editingAnnotationType == "freeText" {
                    Image(systemName: editingAnnotationType == "stickyNote" ? "note.text" : "textbox")
                    TextField("Type text here...", text: $editingAnnotationText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: 250)
                        .onChange(of: editingAnnotationText) { _, newText in
                            PrintablePDFView.current?.updateActiveAnnotationText(newText)
                        }
                } else {
                    Image(systemName: "signature")
                }

                Text(editingAnnotationType == "stickyNote" ? "Drag to move" : "Drag to move, drag corners to resize")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

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

            // Row 2: Font controls (free text only)
            if editingAnnotationType == "freeText" {
                HStack(spacing: 8) {
                    Text("Font:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $editingFontName) {
                        Text("Helvetica").tag("Helvetica")
                        Text("Times").tag("Times New Roman")
                        Text("Courier").tag("Courier")
                        Text("Georgia").tag("Georgia")
                        Text("Arial").tag("Arial")
                        Text("Verdana").tag("Verdana")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .onChange(of: editingFontName) { _, _ in applyFontChange() }

                    Stepper(value: $editingFontSize, in: 8...72, step: 1) {
                        Text("\(Int(editingFontSize))pt")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 32)
                    }
                    .onChange(of: editingFontSize) { _, _ in applyFontChange() }

                    Toggle(isOn: $editingFontBold) {
                        Text("B").fontWeight(.bold)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .onChange(of: editingFontBold) { _, _ in applyFontChange() }

                    Toggle(isOn: $editingFontItalic) {
                        Text("I").italic()
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .onChange(of: editingFontItalic) { _, _ in applyFontChange() }

                    ColorPicker("", selection: $annotationColor)
                        .labelsHidden()
                        .frame(width: 24)
                        .onChange(of: annotationColor) { _, newColor in
                            PrintablePDFView.current?.updateActiveAnnotationFontColor(NSColor(newColor))
                        }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.top, 8)
    }

    private func applyFontChange() {
        var traits: NSFontTraitMask = []
        if editingFontBold { traits.insert(.boldFontMask) }
        if editingFontItalic { traits.insert(.italicFontMask) }

        let fm = NSFontManager.shared
        var font = NSFont(name: editingFontName, size: editingFontSize)
            ?? NSFont.systemFont(ofSize: editingFontSize)
        font = fm.convert(font, toHaveTrait: traits)
        PrintablePDFView.current?.updateActiveAnnotationFont(font)
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

    private var searchPlaceholder: String {
        if isViewingMarkdown { return "Find in document…" }
        return "Search in PDF…"
    }

    /// Route TextField changes to the right find machinery for the current
    /// document. PDF/DOCX/EML keep using PDFKit (already wired via PDFKitView's
    /// `searchText` binding). MD Reader uses WKWebView via mdSearch. MD Quick
    /// is best-effort — Cmd+F still opens this bar, but a meaningful find for
    /// NSTextView is deferred to a future patch; for now the user can switch
    /// to Reader mode.
    private func handleSearchTextChange(_ newValue: String) {
        if isViewingMarkdown && markdownMode == .reader {
            if newValue.isEmpty {
                mdSearch.clear()
            } else {
                mdSearch.find(newValue)
            }
        }
        // PDF mode: PDFKitView observes searchText directly and runs findString.
    }

    private var searchBar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                        .onChange(of: searchText) { _, newValue in
                            handleSearchTextChange(newValue)
                        }
                        .onSubmit {
                            if isViewingMarkdown && markdownMode == .reader {
                                mdSearch.findNext()
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            mdSearch.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if isViewingMarkdown && markdownMode == .reader {
                        Button { mdSearch.findPrev() } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .help("Previous match (Shift+Return)")
                        .disabled(searchText.isEmpty)

                        Button { mdSearch.findNext() } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .help("Next match (Return)")
                        .disabled(searchText.isEmpty)

                        if mdSearch.lastResult == .noMatch && !searchText.isEmpty {
                            Text("No match")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Button {
                        showSearch = false
                        searchText = ""
                        mdSearch.clear()
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
        var types: [UTType] = [.pdf]
        if let emlType = UTType(filenameExtension: "eml") { types.append(emlType) }
        if let docxType = UTType(filenameExtension: "docx") { types.append(docxType) }
        if let mdType = UTType(filenameExtension: "md") { types.append(mdType) }
        panel.allowedContentTypes = types
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
            isViewingEML = false
            emlAttachments = []
            emlMessage = nil
            originalEMLURL = nil
            isViewingDOCX = false
            originalDOCXURL = nil
            docxTempPDFURL = nil
            isViewingMarkdown = false
            originalMarkdownURL = nil
            markdownDocument = nil
            markdownAttributed = nil
            markdownAnchors = [:]
            markdownTOC = []
            markdownStats = .empty
            return
        }
        switch url.pathExtension.lowercased() {
        case "eml":
            loadEMLDocument(from: url)
        case "docx":
            loadDOCXDocument(from: url)
        case "md", "markdown":
            loadMarkdownDocument(from: url)
        default:
            loadPDFDocument(from: url)
        }
    }

    private func renderMarkdownAsPDF() {
        guard let doc = markdownDocument, let url = originalMarkdownURL else { return }
        isRenderingMarkdownPDF = true
        Task {
            do {
                let (pdfDoc, tempURL) = try await MarkdownToPDFConverter.convert(
                    source: doc.source,
                    sourceURL: url,
                    theme: markdownTheme,
                    typography: markdownTypography
                )
                await MainActor.run {
                    pdfDocument = pdfDoc
                    totalPages = pdfDoc.pageCount
                    currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingMarkdown = false
                    markdownDocument = nil
                    markdownAttributed = nil
                    markdownAnchors = [:]
                    renderedPDFTempURL = tempURL
                    pendingRenderedSourceURL = url
                    isRenderingMarkdownPDF = false
                    showSaveRenderedPDFPrompt = true
                }
            } catch {
                await MainActor.run {
                    isRenderingMarkdownPDF = false
                }
            }
        }
    }

    private func confirmSaveRenderedPDF() {
        guard let tempURL = renderedPDFTempURL,
              let sourceURL = pendingRenderedSourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".pdf"
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                renderedPDFTempURL = dest
                pdfURL = dest
            } catch {
                // If move fails, fall back to copy.
                try? FileManager.default.copyItem(at: tempURL, to: dest)
            }
        }
        pendingRenderedSourceURL = nil
    }

    private func loadMarkdownDocument(from url: URL) {
        do {
            let doc = try MarkdownDocument(url: url)
            let (styled, anchors) = doc.styledAttributedStringWithAnchors()
            let (_, toc) = MarkdownToHTML.render(doc.source)
            markdownTOC = toc
            markdownStats = ReadingStats(source: doc.source)
            pdfDocument = nil
            totalPages = 0
            currentPage = 0
            documentVersion = 0
            formFieldCount = 0
            isViewingEML = false
            emlAttachments = []
            emlMessage = nil
            originalEMLURL = nil
            isViewingDOCX = false
            originalDOCXURL = nil
            docxTempPDFURL = nil
            isViewingMarkdown = true
            originalMarkdownURL = url
            markdownDocument = doc
            markdownAttributed = styled
            markdownAnchors = anchors
        } catch {
            isViewingMarkdown = false
            originalMarkdownURL = nil
            markdownDocument = nil
            markdownAttributed = nil
            markdownAnchors = [:]
            markdownTOC = []
            markdownStats = .empty
        }
    }

    private func loadPDFDocument(from url: URL) {
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
                isViewingEML = false
                emlAttachments = []
                emlMessage = nil
                originalEMLURL = nil
                isViewingDOCX = false
                originalDOCXURL = nil
                docxTempPDFURL = nil
                isViewingMarkdown = false
                originalMarkdownURL = nil
                markdownDocument = nil
                markdownAttributed = nil
                markdownAnchors = [:]
                bookmarkManager.load(for: url)
                if isLocked {
                    showPasswordSheet = true
                }
            }
        }
    }

    private func loadDOCXDocument(from url: URL) {
        isConvertingDOCX = true
        docxConversionError = nil
        originalDOCXURL = url
        Task {
            do {
                let (doc, tempURL) = try await DOCXToPDFConverter.convert(url: url)
                await MainActor.run {
                    pdfDocument = doc
                    totalPages = doc.pageCount
                    currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingEML = false
                    emlAttachments = []
                    emlMessage = nil
                    originalEMLURL = nil
                    isViewingDOCX = true
                    docxTempPDFURL = tempURL
                    isViewingMarkdown = false
                    originalMarkdownURL = nil
                    markdownDocument = nil
                    markdownAttributed = nil
                    markdownAnchors = [:]
                    bookmarkManager.load(for: url)
                    isConvertingDOCX = false
                }
            } catch {
                await MainActor.run {
                    docxConversionError = error.localizedDescription
                    isConvertingDOCX = false
                    pdfDocument = nil
                    totalPages = 0
                }
            }
        }
    }

    private func loadEMLDocument(from url: URL) {
        isConvertingEML = true
        emlConversionError = nil
        originalEMLURL = url
        Task {
            do {
                let data = try Data(contentsOf: url)
                let message = try EMLParser.parse(data: data)
                let doc = try await EMLToPDFConverter.convert(message, loadExternalImages: loadExternalImages)
                await MainActor.run {
                    pdfDocument = doc
                    totalPages = doc.pageCount
                    currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingEML = true
                    emlMessage = message
                    emlAttachments = message.attachments
                    isViewingDOCX = false
                    originalDOCXURL = nil
                    docxTempPDFURL = nil
                    isViewingMarkdown = false
                    originalMarkdownURL = nil
                    markdownDocument = nil
                    markdownAttributed = nil
                    markdownAnchors = [:]
                    bookmarkManager.load(for: url)
                    isConvertingEML = false
                }
            } catch {
                await MainActor.run {
                    emlConversionError = error.localizedDescription
                    isConvertingEML = false
                    pdfDocument = nil
                    totalPages = 0
                }
            }
        }
    }

    private func reloadEML() {
        guard let url = originalEMLURL else { return }
        loadEMLDocument(from: url)
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
