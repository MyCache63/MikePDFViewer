import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Observation

/// Page index/count live here so PDF scroll updates do not re-evaluate the
/// whole ContentView tree. Views that display the page number observe this;
/// ContentView itself only writes it from loaders and actions.
@Observable
final class DocumentPageState {
    var currentPage: Int = 0
    var totalPages: Int = 0

    func reset() {
        currentPage = 0
        totalPages = 0
    }
}

struct ContentView: View {
    @State var pdfURL: URL?
    @EnvironmentObject var recentFiles: RecentFilesManager
    /// Only the key window should react to app-wide menu notifications
    /// (Open, zoom, find, etc.). Without this, every open window loads the
    /// same file and shares edits - the multi-window stale-artifact bug.
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openWindow) private var openWindow
    @State private var hostWindow: NSWindow?
    @AppStorage("reuse-open-windows") private var reuseOpenWindows: Bool = true
    @AppStorage("reopenLastDocument") private var reopenLastDocument = true
    @State private var pdfDocument: PDFDocument?
    @State private var pageState = DocumentPageState()
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showSearch = false
    @State private var showMergeSheet = false
    @State private var sidebarVisible = true
    @State private var showOCRSheet = false
    @State private var isMakingSearchable = false
    @State private var makeSearchableProgress: Double = 0
    @State private var makeSearchableCancelFlag = SearchableOCRService.CancelFlag()
    @State private var makeSearchableMessage: String?
    @State private var showRebuildTextPrompt = false
    @State private var errorAlertMessage: String?
    /// File the sandbox refused to read; drives the Permission Needed alert.
    @State private var accessRequestURL: URL?

    // Unsaved-changes tracking: set on any document mutation, cleared on
    // load and successful save. Guards both open-another-file and app quit.
    @State private var documentDirty = false
    @State private var lastLoadedURL: URL?
    @State private var pendingOpenURL: URL?
    @State private var showDiscardChangesAlert = false
    @State private var isRevertingOpen = false
    /// Incremented on every open attempt; async completions that finish after
    /// a newer open are discarded so a slow load cannot overwrite a fast one.
    @State private var loadGeneration: UInt64 = 0
    @State private var isLoadingDocument = false
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
    /// Full-screen presentation runs in its own borderless window (see
    /// PresentationWindowController), not a sheet, so it can cover the screen.
    private func startPresentation() {
        guard let document = pdfDocument else { return }
        PresentationWindowController.shared.present(document: document, startPage: pageState.currentPage)
    }
    @State private var showSignatureSheet = false
    @State private var showRedactConfirm = false
    @State private var showPasswordSheet = false
    @State private var showEncryptSheet = false
    @State private var showWatermarkSheet = false
    @State private var showExportImages = false
    /// Non-PDF modes convert to a PDF first; it is held here for the image sheet.
    @State private var exportImagesDocument: PDFDocument?
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

    // Plain text (.txt/.log) viewer
    @State private var isViewingText: Bool = false
    @State private var originalTextURL: URL?
    @State private var textFileContent: String = ""
    @AppStorage("txt-font-name") private var txtFontName: String = "Menlo"
    @AppStorage("txt-font-size") private var txtFontSize: Double = 13

    // Quick Look viewer (.pptx/.ppt, and instant default for .docx)
    @State private var isViewingQuickLook: Bool = false
    @State private var quickLookURL: URL?

    // HTML mini browser (.html/.htm)
    @State private var isViewingHTML: Bool = false
    @State private var originalHTMLURL: URL?
    @State private var isViewingSVG: Bool = false
    @State private var originalSVGURL: URL?
    @State private var isViewingImage: Bool = false
    @State private var originalImageURL: URL?
    @StateObject private var imageViewer = ImageViewerController()
    @State private var zoomLevel: Double = 1.0
    @State private var loadStartedAt: Date?
    @State private var loadKind: String = ""
    @State private var didInitialLoad = false
    @State private var textFileLineCount: Int = 0
    @State private var textFileAttributed = NSAttributedString()
    @State private var isViewingCSV: Bool = false
    @State private var originalCSVURL: URL?
    @State private var csvDocument: CSVDocument?
    @AppStorage("csv-first-row-is-header") private var csvFirstRowIsHeader: Bool = true
    @StateObject private var htmlBrowser = HTMLBrowserController()


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
    @State private var showMarkdownPrintSheet: Bool = false
    @State private var renderedPDFTempURL: URL?
    @State private var pendingRenderedSourceURL: URL?
    @State private var showSaveRenderedPDFPrompt: Bool = false
    @StateObject private var bookmarkManager = BookmarkManager()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// True when this scene is the key window. Menu commands post globally;
    /// only the key scene should apply them.
    private var isKeyScene: Bool {
        controlActiveState == .key
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
            .sheet(isPresented: $showMarkdownPrintSheet) {
                if let doc = markdownDocument, let url = originalMarkdownURL {
                    MarkdownPrintSheet(
                        source: doc.source,
                        sourceURL: url,
                        theme: markdownTheme,
                        baseTypography: markdownTypography
                    ) { pdf in
                        // Let the sheet finish closing before the print panel
                        // attaches to the key window.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            runPrintOperation(for: pdf)
                        }
                    }
                }
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
            .sheet(isPresented: $isMakingSearchable) {
                makeSearchableProgressSheet
            }
            .alert("Make Searchable", isPresented: makeSearchableAlertShown) {
                Button("OK") { makeSearchableMessage = nil }
            } message: {
                Text(makeSearchableMessage ?? "")
            }
            .alert("Rebuild the text layer?", isPresented: $showRebuildTextPrompt) {
                Button("Rebuild", role: .destructive) { makeSearchable(mode: .rebuildAll) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This document already carries text, but some PDFs, especially ones exported by Chrome, place that text where it cannot be clicked or found. Rebuilding reads every page with OCR and replaces the text. Each page becomes an image, so the file grows and the pages stop being vector. Your original file is untouched until you use Save As.")
            }
            .alert("Problem", isPresented: errorAlertShown) {
                Button("OK") { errorAlertMessage = nil }
            } message: {
                Text(errorAlertMessage ?? "")
            }
            .alert("Unsaved Changes", isPresented: $showDiscardChangesAlert) {
                Button("Cancel", role: .cancel) { pendingOpenURL = nil }
                Button("Discard and Open", role: .destructive) {
                    documentDirty = false
                    if let url = pendingOpenURL { pdfURL = url }
                    pendingOpenURL = nil
                }
            } message: {
                Text("The current document has unsaved edits (annotations, OCR, or page changes). Press Cancel and use Cmd+S to keep them, or discard them and open the new file.")
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
                        pageState.totalPages = document.pageCount
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
            .sheet(isPresented: $showExportImages, onDismiss: { exportImagesDocument = nil }) {
                if let document = exportImagesDocument ?? pdfDocument {
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
                onGoToPage: { if pageState.totalPages > 0 { goToPageText = ""; showGoToPage = true } }
            ))
    }

    /// First half of the notification wiring, split from
    /// `viewWithNotifications` so the type-checker can cope with the chain.
    private var viewWithDocumentNotifications: some View {
        viewWithAlerts
            .onReceive(NotificationCenter.default.publisher(for: .pdfDocumentModified)) { notification in
                // Prefer document identity (posts now carry the PDFDocument);
                // fall back to key-window for older nil-object posts.
                if let doc = notification.object as? PDFDocument {
                    guard doc === pdfDocument else { return }
                } else {
                    guard isKeyScene else { return }
                }
                documentVersion += 1
                documentDirty = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfDocumentSaved)) { notification in
                if let doc = notification.object as? PDFDocument {
                    guard doc === pdfDocument else { return }
                } else {
                    guard isKeyScene else { return }
                }
                documentDirty = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfAnnotationEditingChanged)) { notification in
                if let doc = notification.object as? PDFDocument {
                    guard doc === pdfDocument else { return }
                } else {
                    guard isKeyScene else { return }
                }
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
                guard isKeyScene else { return }
                darkModeReading.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfSetDisplayMode)) { notification in
                guard isKeyScene else { return }
                if let rawValue = notification.userInfo?["mode"] as? Int,
                   let mode = PDFDisplayMode(rawValue: rawValue) {
                    displayMode = mode
                }
            }
    }

    private var viewWithNotifications: some View {
        viewWithDocumentNotifications
            .onReceive(NotificationCenter.default.publisher(for: .pdfToggleBookmark)) { _ in
                guard isKeyScene else { return }
                if pdfDocument != nil { bookmarkManager.toggleBookmark(for: pageState.currentPage) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfExtractPages)) { _ in
                guard isKeyScene else { return }
                if pdfDocument != nil { showExtractSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfMakeSearchable)) { _ in
                guard isKeyScene else { return }
                makeSearchable()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfRebuildTextLayer)) { _ in
                guard isKeyScene, pdfDocument != nil else { return }
                showRebuildTextPrompt = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfPrint)) { _ in
                guard isKeyScene else { return }
                handlePrint()
            }
            .modifier(ZoomCommandsListener(
                onZoomIn: { guard isKeyScene else { return }; nudgeZoom(0.1) },
                onZoomOut: { guard isKeyScene else { return }; nudgeZoom(-0.1) }))
            .onReceive(NotificationCenter.default.publisher(for: .pdfExport)) { notification in
                guard isKeyScene else { return }
                if let raw = notification.userInfo?["format"] as? String,
                   let format = ExportFormat(rawValue: raw) {
                    exportDocument(format)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfGoToPage)) { _ in
                guard isKeyScene else { return }
                if pageState.totalPages > 0 {
                    goToPageText = ""
                    showGoToPage = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfShowMerge)) { _ in
                guard isKeyScene else { return }
                showMergeSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfOpenFile)) { notification in
                // Critical: Open / Recent must not replace every window's document.
                guard isKeyScene else { return }
                if let url = notification.userInfo?["url"] as? URL {
                    recentFiles.add(url)
                    if raiseWindowAlreadyShowing(url) { return }
                    pdfURL = url
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfToggleSplitView)) { _ in
                guard isKeyScene else { return }
                if pdfDocument != nil {
                    showSplitView.toggle()
                    if showSplitView { splitCurrentPage = pageState.currentPage }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pdfStartPresentation)) { _ in
                guard isKeyScene else { return }
                startPresentation()
            }
            .modifier(FindCommandsListener(
                onShowFind: { guard isKeyScene else { return }; handleShowFindCommand() },
                onFindNext: { guard isKeyScene else { return }; handleFindNextCommand() },
                onFindPrev: { guard isKeyScene else { return }; handleFindPrevCommand() }
            ))
            .onChange(of: pdfURL) { _, newURL in loadDocument(from: newURL) }
            .onChange(of: documentDirty) { _, dirty in
                // Track unsaved state across windows: set true if this window
                // is dirty; only clear the app flag when this key window saves
                // and no other path re-sets it. Best-effort for multi-window.
                if dirty {
                    AppDelegate.hasUnsavedChanges = true
                } else if isKeyScene {
                    AppDelegate.hasUnsavedChanges = false
                }
            }
            .onAppear { handleAppear() }
            .modifier(TextFontChangeListener(fontName: txtFontName,
                                             fontSize: txtFontSize,
                                             onChange: rebuildTextAttributed))
            .modifier(AccessRequestAlert(url: $accessRequestURL, onGrant: grantAccessAndReload))
            .onOpenURL { url in
                didInitialLoad = true
                recentFiles.add(url)
                if raiseWindowAlreadyShowing(url) { return }
                pdfURL = url
            }
            .background(WindowAccessor { window in
                guard hostWindow !== window else { return }
                hostWindow = window
                OpenDocumentRegistry.shared.update(url: pdfURL, for: window)
            })
            .onDisappear { OpenDocumentRegistry.shared.forget(hostWindow) }
    }

    /// If this file is already open somewhere, bring that window forward and
    /// report true so the caller skips loading a second copy.
    private func raiseWindowAlreadyShowing(_ url: URL) -> Bool {
        guard reuseOpenWindows else { return false }

        // Already the front document in THIS window: nothing to load.
        if let current = pdfURL,
           OpenDocumentRegistry.key(for: current) == OpenDocumentRegistry.key(for: url) {
            hostWindow?.makeKeyAndOrderFront(nil)
            return true
        }

        guard let existing = OpenDocumentRegistry.shared.window(showing: url,
                                                               excluding: hostWindow) else {
            return false
        }
        if existing.isMiniaturized { existing.deminiaturize(nil) }
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func handleAppear() {
        PerfLog.shared.markFirstWindow()
        // Reopening the last file used to run inside the first view update,
        // which added 150 to 300 ms before the window appeared. One turn of
        // the run loop later, the window is already on screen.
        DispatchQueue.main.async {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            if pdfURL == nil && reopenLastDocument,
               let lastURL = recentFiles.mostRecentExistingURL {
                pdfURL = lastURL
            } else {
                loadDocument(from: pdfURL)
            }
        }
    }

    private func handleShowFindCommand() {
        if pdfDocument != nil || isViewingMarkdown || isViewingText {
            showSearch.toggle()
            if !showSearch {
                searchText = ""
                mdSearch.clear()
            }
        }
    }

    private func handleFindNextCommand() {
        if isViewingMarkdown && markdownMode == .reader {
            mdSearch.findNext()
        }
    }

    private func handleFindPrevCommand() {
        if isViewingMarkdown && markdownMode == .reader {
            mdSearch.findPrev()
        }
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
                .overlay(alignment: .bottomTrailing) { zoomOverlay }
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
            BoundThumbnailSidebar(
                document: document,
                pageState: pageState,
                documentVersion: documentVersion,
                bookmarkManager: bookmarkManager,
                onMovePage: { from, to in
                    movePage(from: from, to: to)
                },
                onDeletePages: { pageIndices in
                    deletePages(pageIndices)
                }
            )
            // Force a full sidebar identity reset when the PDFDocument instance
            // changes so SwiftUI does not reuse page-row @State (old thumbnails).
            .id(ObjectIdentifier(document))
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
        } else if isViewingImage {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(imageViewer.dimensionsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(imageViewer.fileSizeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let url = originalImageURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxHeight: .infinity)
        } else if isViewingCSV {
            VStack(spacing: 4) {
                Image(systemName: "tablecells")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                if let table = csvDocument {
                    Text(table.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(table.delimiterName) separated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let url = originalCSVURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxHeight: .infinity)
        } else if isViewingHTML {
            VStack {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                if !htmlBrowser.pageTitle.isEmpty {
                    Text(htmlBrowser.pageTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                if let url = originalHTMLURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }
            .frame(maxHeight: .infinity)
        } else if isViewingQuickLook {
            VStack {
                Image(systemName: "eye")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Quick Look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = quickLookURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }
            .frame(maxHeight: .infinity)
        } else if isViewingText {
            VStack {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("\(textFileLineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = originalTextURL {
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }
            .frame(maxHeight: .infinity)
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
    }

    @ViewBuilder
    private var pdfContentWithEMLSidebar: some View {
        if isViewingMarkdown, let doc = markdownDocument {
            ZStack {
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
                if showSearch {
                    searchBar
                }
            }
        } else if isViewingText {
            ZStack {
                MarkdownView(attributedString: textFileAttributed,
                             anchors: [:],
                             liveSearchText: $searchText)
                if showSearch {
                    searchBar
                }
            }
        } else if isViewingQuickLook, let qlURL = quickLookURL {
            QuickLookFileView(url: qlURL)
        } else if isViewingImage {
            ImageViewerView(controller: imageViewer)
        } else if isViewingCSV, let table = csvDocument {
            CSVTableView(document: table, fontScale: zoomLevel)
        } else if isViewingSVG {
            HTMLBrowserView(controller: htmlBrowser)
        } else if isViewingHTML {
            HTMLBrowserView(controller: htmlBrowser)
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
                BoundPDFKitView(
                    document: document,
                    pageState: pageState,
                    searchText: debouncedSearchText,
                    darkMode: darkModeReading,
                    displayMode: displayMode
                )
                .id(ObjectIdentifier(document))
            } else if isLoadingDocument {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                    if let name = pdfURL?.lastPathComponent {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }

            if showSearch, (pdfDocument != nil || isViewingMarkdown) {
                // Spacer must not eat clicks or PDF/text selection dies
                // while the find bar is open.
                searchBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if annotationEditingMode {
                VStack {
                    annotationEditingBanner
                    Spacer().allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Toolbar Groups

    @ViewBuilder
    private var fileToolbar: some View {
        Button { openPDF() } label: { Image(systemName: "folder") }
            .tooltip("Open PDF (Cmd+O)")

        Button { saveDocumentAs() } label: { Image(systemName: "square.and.arrow.down") }
            .tooltip("Save As (Shift+Cmd+S)")
            .disabled(pdfDocument == nil)

        Button { handlePrint() } label: { Image(systemName: "printer") }
            .tooltip("Print (Cmd+P)")
            .disabled(!canPrint)

        if let url = pdfURL {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                .tooltip("Share PDF")
        }

        Menu {
            Button(ExportFormat.pdf.menuTitle) { exportDocument(.pdf) }
            Button(ExportFormat.docx.menuTitle) { exportDocument(.docx) }
            Button(ExportFormat.png.menuTitle) { exportDocument(.png) }
        } label: {
            Image(systemName: "square.and.arrow.up.on.square")
        }
        .tooltip("Export as PDF, Word, or PNG (File > Export)")
        .disabled(!canExport)

        Button { openWindow(id: "notepad") } label: { NotepadIconView() }
            .tooltip("Notepad (Shift+Cmd+N)")

        OpenWithMenu(fileURL: openWithSourceURL, fileKind: openWithFileKind)

        if isViewingText {
            textFontMenu
        }

        if isViewingImage {
            Button { imageViewer.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .tooltip("Zoom Out")

            Button { imageViewer.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .tooltip("Zoom In")

            Button { imageViewer.fitToWindow() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .tooltip("Fit to Window")

            Button { imageViewer.actualSize() } label: {
                Image(systemName: "1.magnifyingglass")
            }
            .tooltip("Actual Size")
        }

        if isViewingCSV {
            Toggle(isOn: $csvFirstRowIsHeader) {
                Image(systemName: "tablecells.badge.ellipsis")
            }
            .toggleStyle(.button)
            .tooltip("Use the first row as column headings")
            .onChange(of: csvFirstRowIsHeader) { _, _ in reparseCSV() }
        }

        if isViewingSVG {
            Button { htmlBrowser.svgZoom("out") } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .tooltip("Zoom Out")

            Button { htmlBrowser.svgZoom("in") } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .tooltip("Zoom In")

            Button { htmlBrowser.svgZoom("fit") } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .tooltip("Fit to Window")

            Button { htmlBrowser.svgZoom("actual") } label: {
                Image(systemName: "1.magnifyingglass")
            }
            .tooltip("Actual Size")
        }

        if isViewingHTML {
            Button { htmlBrowser.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .tooltip("Back")
            .disabled(!htmlBrowser.canGoBack)

            Button { htmlBrowser.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .tooltip("Forward")
            .disabled(!htmlBrowser.canGoForward)

            Button { htmlBrowser.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .tooltip("Reload")

            Button {
                if let url = originalHTMLURL { htmlBrowser.load(fileURL: url) }
            } label: {
                Image(systemName: "house")
            }
            .tooltip("Back to the opened file")
        }

        if isViewingQuickLook, let docxURL = originalDOCXURL {
            Button {
                loadDOCXDocument(from: docxURL)
            } label: {
                if isConvertingDOCX {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "doc.richtext")
                }
            }
            .tooltip("Convert to PDF (enables search, annotate, print; slower)")
            .disabled(isConvertingDOCX)
        }

        if isViewingMarkdown {
            Button {
                markdownMode = (markdownMode == .reader) ? .quick : .reader
                if markdownMode == .quick { ensureMarkdownAttributed() }
            } label: {
                Image(systemName: markdownMode == .reader ? "book" : "doc.plaintext")
            }
            .tooltip(markdownMode == .reader ? "Switch to Quick view" : "Switch to Reader view")

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
                .tooltip("Reading Theme — \(markdownTheme.displayName)")

                Button { showMarkdownSettings.toggle() } label: {
                    Image(systemName: "textformat.size")
                }
                .tooltip("Typography & Focus Mode")
                .popover(isPresented: $showMarkdownSettings, arrowEdge: .bottom) {
                    MarkdownReaderSettings(
                        typography: markdownTypographyBinding,
                        focusMode: $mdFocusMode
                    )
                }

                Button { mdTOCVisible.toggle() } label: {
                    Image(systemName: mdTOCVisible ? "list.bullet.indent" : "list.bullet")
                }
                .tooltip(mdTOCVisible ? "Hide Table of Contents" : "Show Table of Contents")
            }

            Button { renderMarkdownAsPDF() } label: {
                if isRenderingMarkdownPDF {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "doc.richtext")
                }
            }
            .tooltip("Render as PDF")
            .disabled(isRenderingMarkdownPDF)
        }

        Divider()

        Button {
            showSearch.toggle()
            if !showSearch { searchText = "" }
        } label: { Image(systemName: "magnifyingglass") }
            .tooltip("Search (Cmd+F)")
    }

    /// Quick font switcher for the plain-text viewer: a few sensible
    /// families (monospace first) plus size up/down. Persisted, so the next
    /// .txt opens the same way.
    private static let txtFontChoices: [(label: String, name: String)] = [
        ("Menlo (mono)", "Menlo"),
        ("SF Mono", "SF Mono"),
        ("Courier New (mono)", "Courier New"),
        ("System (SF Pro)", ".AppleSystemUIFont"),
        ("Helvetica Neue", "Helvetica Neue"),
        ("Georgia", "Georgia"),
        ("Times New Roman", "Times New Roman"),
    ]

    private var textFontMenu: some View {
        Menu {
            ForEach(Self.txtFontChoices, id: \.name) { choice in
                Button {
                    txtFontName = choice.name
                } label: {
                    HStack {
                        Text(choice.label)
                        if txtFontName == choice.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Bigger (\(Int(txtFontSize)) pt)") {
                txtFontSize = min(txtFontSize + 1, 32)
            }
            .keyboardShortcut("+", modifiers: [.command, .option])
            Button("Smaller") {
                txtFontSize = max(txtFontSize - 1, 8)
            }
            .keyboardShortcut("-", modifiers: [.command, .option])
            Button("Reset to Menlo 13") {
                txtFontName = "Menlo"
                txtFontSize = 13
            }
        } label: {
            Image(systemName: "textformat")
        }
        .tooltip("Text font: \(txtFontName) \(Int(txtFontSize)) pt")
    }

    @ViewBuilder
    private var viewToolbar: some View {
        Button { NotificationCenter.default.post(name: .pdfZoomOut, object: nil) } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .tooltip("Zoom Out").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfZoomIn, object: nil) } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .tooltip("Zoom In").disabled(pdfDocument == nil)

        Button { darkModeReading.toggle() } label: {
            Image(systemName: darkModeReading ? "sun.max" : "moon")
        }
        .tooltip(darkModeReading ? "Light Mode" : "Dark Reading Mode").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfRotateLeft, object: nil) } label: {
            Image(systemName: "rotate.left")
        }
        .tooltip("Rotate Left (Cmd+Option+L)").disabled(pdfDocument == nil)

        Button { NotificationCenter.default.post(name: .pdfRotateRight, object: nil) } label: {
            Image(systemName: "rotate.right")
        }
        .tooltip("Rotate Right (Cmd+Option+R)").disabled(pdfDocument == nil)

        Picker("", selection: $displayMode) {
            Text("Continuous").tag(PDFDisplayMode.singlePageContinuous)
            Text("Single Page").tag(PDFDisplayMode.singlePage)
            Text("Two Pages").tag(PDFDisplayMode.twoUp)
            Text("Two Pages Scroll").tag(PDFDisplayMode.twoUpContinuous)
        }
        .pickerStyle(.menu).frame(width: 130)
        .tooltip("Display Mode").disabled(pdfDocument == nil)

        Button { showSplitView.toggle(); if showSplitView { splitCurrentPage = pageState.currentPage } } label: {
            Image(systemName: showSplitView ? "rectangle" : "rectangle.split.2x1")
        }
        .tooltip(showSplitView ? "Close Split View" : "Split View").disabled(pdfDocument == nil)

        Button { startPresentation() } label: {
            Image(systemName: "play.rectangle")
        }
        .tooltip("Full Screen Presentation (Cmd+L)").disabled(pdfDocument == nil)
    }

    @ViewBuilder
    private var toolsToolbar: some View {
        Button { showAnnotationBar.toggle() } label: {
            Image(systemName: "pencil.tip.crop.circle")
        }
        .tooltip("Markup Tools").disabled(pdfDocument == nil)

        BookmarkToolbarButton(
            pageState: pageState,
            bookmarkManager: bookmarkManager,
            enabled: pdfDocument != nil
        )

        Button { showExtractSheet = true } label: {
            Image(systemName: "doc.badge.plus")
        }
        .tooltip("Extract Pages").disabled(pdfDocument == nil)

        Button { showSignatureSheet = true } label: {
            Image(systemName: "signature")
        }
        .tooltip("Add Signature").disabled(pdfDocument == nil)

        Button {
            showRedactConfirm = true
        } label: {
            Image(systemName: "eye.slash")
        }
        .tooltip("Redact Selection (select text first)").disabled(pdfDocument == nil)

        Button { showOCRSheet = true } label: {
            Image(systemName: "doc.text.magnifyingglass")
        }
        .tooltip("OCR Document").disabled(pdfDocument == nil)

        Button { makeSearchable() } label: {
            Image(systemName: "text.viewfinder")
        }
        .tooltip("Make Searchable (on-device OCR, adds a text layer so Cmd+F works on scans)")
        .disabled(pdfDocument == nil || isMakingSearchable)

        Button { showEncryptSheet = true } label: {
            Image(systemName: "lock.shield")
        }
        .tooltip("Password Protect").disabled(pdfDocument == nil)

        Button { showWatermarkSheet = true } label: {
            Image(systemName: "drop.triangle")
        }
        .tooltip("Add Watermark").disabled(pdfDocument == nil)

        Button { showExportImages = true } label: {
            Image(systemName: "photo.on.rectangle")
        }
        .tooltip("Export as Images").disabled(pdfDocument == nil)

        Button { showCompareSheet = true } label: {
            Image(systemName: "square.split.2x1")
        }
        .tooltip("Compare PDFs").disabled(pdfDocument == nil)

        Button { showMergeSheet = true } label: {
            Image(systemName: "doc.on.doc")
        }
        .tooltip("Merge PDFs")
    }

    @ViewBuilder
    private var statusToolbar: some View {
        PageStatusControl(
            pageState: pageState,
            showGoToPage: $showGoToPage,
            goToPageText: $goToPageText,
            onNavigate: { navigateToPage() }
        )

        if formFieldCount > 0 {
            Label("\(formFieldCount) fields", systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.caption2)
                .foregroundStyle(.orange)
        }

        Text("v\(appVersion)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Make Searchable (on-device OCR)

    private var makeSearchableAlertShown: Binding<Bool> {
        Binding(
            get: { makeSearchableMessage != nil },
            set: { if !$0 { makeSearchableMessage = nil } }
        )
    }

    private var errorAlertShown: Binding<Bool> {
        Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )
    }

    private var makeSearchableProgressSheet: some View {
        VStack(spacing: 12) {
            Text("Making PDF Searchable")
                .font(.headline)
            ProgressView(value: makeSearchableProgress)
                .frame(width: 260)
            Text("Recognizing text on-device with Apple Vision…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") {
                makeSearchableCancelFlag.cancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }

    private func makeSearchable(mode: SearchableOCRService.TextLayerMode = .addWhereMissing) {
        guard let document = pdfDocument, !isMakingSearchable else { return }
        isMakingSearchable = true
        makeSearchableProgress = 0
        let cancelFlag = SearchableOCRService.CancelFlag()
        makeSearchableCancelFlag = cancelFlag
        let sourceID = ObjectIdentifier(document)
        let generationAtStart = loadGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try SearchableOCRService.makeSearchable(document: document, mode: mode, cancelFlag: cancelFlag) { done, total in
                    let fraction = Double(done) / Double(max(total, 1))
                    DispatchQueue.main.async { makeSearchableProgress = fraction }
                }
                DispatchQueue.main.async {
                    isMakingSearchable = false
                    // User opened another file while OCR ran - drop the result.
                    guard generationAtStart == loadGeneration,
                          let current = pdfDocument,
                          ObjectIdentifier(current) == sourceID else { return }
                    guard let newDoc = PDFDocument(data: result.data) else {
                        makeSearchableMessage = "OCR finished but the rebuilt PDF could not be loaded. The original document is unchanged."
                        return
                    }
                    let pageBefore = pageState.currentPage
                    pdfDocument = newDoc
                    pageState.totalPages = newDoc.pageCount
                    pageState.currentPage = min(pageBefore, max(newDoc.pageCount - 1, 0))
                    documentVersion += 1
                    documentDirty = true
                    if mode == .rebuildAll {
                        makeSearchableMessage = "Rebuilt the text layer on \(result.ocrPageCount) page\(result.ocrPageCount == 1 ? "" : "s"). Selecting, copying and Cmd+F should work now. The pages are images, so use Save As and keep the original."
                    } else {
                        makeSearchableMessage = "Added searchable text to \(result.ocrPageCount) page\(result.ocrPageCount == 1 ? "" : "s"). Cmd+F now works. Press Cmd+S to save."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isMakingSearchable = false
                    // A user-initiated cancel needs no follow-up alert.
                    switch error as? SearchableOCRService.ServiceError {
                    case .cancelled:
                        break   // the user asked for it, no alert needed
                    case .alreadySearchable:
                        // Text exists, but it may be the unusable kind.
                        showRebuildTextPrompt = true
                    default:
                        makeSearchableMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func navigateToPage() {
        guard let pageNum = Int(goToPageText),
              pageNum >= 1, pageNum <= pageState.totalPages else { return }
        pageState.currentPage = pageNum - 1
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
        if isViewingMarkdown || isViewingText { return "Find in document…" }
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
        // PDF mode: PDFKitView observes debouncedSearchText and runs
        // findString. findString walks the whole document synchronously, so
        // waiting 200 ms for typing to pause keeps large PDFs responsive.
        searchDebounceTask?.cancel()
        if newValue.isEmpty {
            debouncedSearchText = ""
        } else {
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue
            }
        }
    }

    private var searchBar: some View {
        VStack {
            HStack {
                Spacer().allowsHitTesting(false)
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
                        .tooltip("Clear search")
                    }
                    if isViewingMarkdown && markdownMode == .reader {
                        Button { mdSearch.findPrev() } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .tooltip("Previous match (Shift+Return)")
                        .disabled(searchText.isEmpty)

                        Button { mdSearch.findNext() } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .tooltip("Next match (Return)")
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
            Spacer().allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func openPDF() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.pdf, .plainText, .json]
        if let emlType = UTType(filenameExtension: "eml") { types.append(emlType) }
        if let docxType = UTType(filenameExtension: "docx") { types.append(docxType) }
        if let mdType = UTType(filenameExtension: "md") { types.append(mdType) }
        if let logType = UTType(filenameExtension: "log") { types.append(logType) }
        if let pptxType = UTType(filenameExtension: "pptx") { types.append(pptxType) }
        if let pptType = UTType(filenameExtension: "ppt") { types.append(pptType) }
        if let keyType = UTType(filenameExtension: "key") { types.append(keyType) }
        types.append(.html)
        types.append(.svg)
        types.append(contentsOf: [.png, .jpeg, .gif, .heic, .tiff, .bmp, .webP, .image])
        types.append(contentsOf: [.commaSeparatedText, .tabSeparatedText])
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
        // Always suggest a .pdf name; the source may be .docx/.eml/.md whose
        // extension must not be reused for PDF bytes.
        let stem = pdfURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = stem + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            if document.write(to: url) {
                NotificationCenter.default.post(name: .pdfDocumentSaved, object: document)
            } else {
                errorAlertMessage = "Could not write to \(url.path). Check that the location is writable and the disk has space."
            }
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
        pageState.totalPages = document.pageCount
        if pageState.currentPage >= pageState.totalPages {
            pageState.currentPage = max(0, pageState.totalPages - 1)
        }
        documentVersion += 1
        documentDirty = true
        NotificationCenter.default.post(name: .pdfDocumentModified, object: document)
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
        documentDirty = true

        // Update current page to follow the moved page
        if pageState.currentPage == source {
            pageState.currentPage = destination
        } else if source < destination && pageState.currentPage > source && pageState.currentPage <= destination {
            pageState.currentPage -= 1
        } else if source > destination && pageState.currentPage >= destination && pageState.currentPage < source {
            pageState.currentPage += 1
        }
    }

    private func loadDocument(from url: URL?) {
        // Re-entry from the revert below: pdfURL was put back to the current
        // document, nothing to load.
        if isRevertingOpen {
            isRevertingOpen = false
            return
        }
        // Unsaved edits guard: don't silently replace a modified document.
        if documentDirty, let url, url != lastLoadedURL {
            pendingOpenURL = url
            showDiscardChangesAlert = true
            isRevertingOpen = true
            pdfURL = lastLoadedURL
            return
        }
        documentDirty = false
        lastLoadedURL = url
        // Keep the registry in step so another window can find this document.
        OpenDocumentRegistry.shared.update(url: url, for: hostWindow)

        // Invalidate any in-flight async load from a previous open.
        loadGeneration &+= 1
        let generation = loadGeneration

        guard let url else {
            clearAllViewerState()
            finishLoad()
            return
        }

        // Drop the previous document immediately so title/content cannot show
        // a mix of old pages and a new filename while the new file loads.
        clearAllViewerState()
        zoomLevel = 1.0
        loadStartedAt = Date()
        loadKind = url.pathExtension.lowercased()
        isLoadingDocument = true
        bookmarkManager.load(for: nil)

        switch url.pathExtension.lowercased() {
        case "eml":
            loadEMLDocument(from: url, generation: generation)
        case "docx", "pptx", "ppt", "key":
            // Instant, format-faithful Quick Look. DOCX keeps a toolbar
            // button to run the slower convert-to-PDF pipeline when PDF
            // features (annotate, print, search) are needed.
            loadQuickLookDocument(from: url, generation: generation)
        case "md", "markdown":
            loadMarkdownDocument(from: url, generation: generation)
        case "txt", "text", "log", "json":
            loadTextDocument(from: url, generation: generation)
        case "html", "htm":
            loadHTMLDocument(from: url, generation: generation)
        case "svg":
            loadSVGDocument(from: url, generation: generation)
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp":
            loadImageDocument(from: url, generation: generation)
        case "csv", "tsv":
            loadCSVDocument(from: url, generation: generation)
        default:
            loadPDFDocument(from: url, generation: generation)
        }
    }

    /// Wipes every mode flag and document binding. Call at the start of every
    /// open so leftovers from the previous file cannot remain on screen.
    private func clearAllViewerState() {
        pdfDocument = nil
        pageState.reset()
        documentVersion = 0
        formFieldCount = 0
        searchText = ""
        debouncedSearchText = ""
        showSearch = false
        showSplitView = false
        showAnnotationBar = false
        annotationEditingMode = false
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
        pendingMDAnchor = nil
        mdSearch.clear()
        isViewingText = false
        originalTextURL = nil
        textFileContent = ""
        textFileLineCount = 0
        textFileAttributed = NSAttributedString()
        isViewingQuickLook = false
        quickLookURL = nil
        isViewingHTML = false
        originalHTMLURL = nil
        isViewingSVG = false
        originalSVGURL = nil
        isViewingImage = false
        originalImageURL = nil
        imageViewer.clear()
        isViewingCSV = false
        originalCSVURL = nil
        csvDocument = nil
    }

    /// One exit point for every loader, so each open is timed once.
    private func finishLoad() {
        isLoadingDocument = false
        guard let started = loadStartedAt else { return }
        loadStartedAt = nil
        PerfLog.shared.record("open .\(loadKind)", since: started,
                              detail: lastLoadedURL?.lastPathComponent ?? "")
    }

    /// Returns false (and skips applying results) when a newer open superseded
    /// this load. Call on the main actor at the start of every async completion.
    @discardableResult
    private func acceptLoadIfCurrent(generation: UInt64, url: URL) -> Bool {
        generation == loadGeneration && pdfURL == url
    }

    private func loadHTMLDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        isViewingHTML = true
        originalHTMLURL = url
        htmlBrowser.load(fileURL: url)
        finishLoad()
    }

    private func loadImageDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let payload = try ImageViewerController.loadPayload(at: url)
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    imageViewer.apply(payload)
                    isViewingImage = true
                    originalImageURL = url
                    finishLoad()
                }
            } catch {
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    handleOpenFailure(url: url, error: error)
                }
            }
        }
    }

    /// Parsing happens off the main thread: a big export can run to megabytes.
    private func loadCSVDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        let treatFirstRowAsHeader = csvFirstRowIsHeader
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) ?? ""
                let delimiter = CSVDocument.detectDelimiter(text: text,
                                                            fileExtension: url.pathExtension)
                let parsed = CSVDocument.parse(text: text, delimiter: delimiter,
                                               firstRowIsHeader: treatFirstRowAsHeader)
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    csvDocument = parsed
                    isViewingCSV = true
                    originalCSVURL = url
                    finishLoad()
                }
            } catch {
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    handleOpenFailure(url: url, error: error)
                }
            }
        }
    }

    /// Re-reads the file when the header toggle changes.
    private func reparseCSV() {
        guard isViewingCSV, let url = originalCSVURL else { return }
        loadGeneration &+= 1
        loadCSVDocument(from: url, generation: loadGeneration)
    }

    /// SVG is vector XML, so WebKit draws it and it stays sharp at any zoom.
    private func loadSVGDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        isViewingSVG = true
        originalSVGURL = url
        _ = htmlBrowser.loadSVG(fileURL: url)
        finishLoad()
    }

    private func loadQuickLookDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        originalDOCXURL = url.pathExtension.lowercased() == "docx" ? url : nil
        isViewingQuickLook = true
        quickLookURL = url
        finishLoad()
    }

    private func loadTextDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        Task.detached(priority: .userInitiated) {
            let result = Self.readTextFile(at: url)
            let content = result.content
            let failure = result.failure
            let lines = result.lines
            await MainActor.run {
                guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                guard let content else {
                    let rebuilt = failure.map {
                        NSError(domain: $0.domain, code: $0.code,
                                userInfo: [NSLocalizedDescriptionKey: $0.message])
                    }
                    handleOpenFailure(url: url, error: rebuilt)
                    return
                }
                isViewingText = true
                originalTextURL = url
                textFileContent = content
                textFileLineCount = lines
                rebuildTextAttributed()
                finishLoad()
            }
        }
    }

    /// Attributed plain text in the user's chosen viewer font. Recomputed
    /// when the font name/size settings change, which is what makes the
    /// toolbar font menu take effect immediately.
    /// Reads a text file and counts its lines away from the main thread. The
    /// line count used to be computed inside the view body, where it cost
    /// 147 ms on a 10 MB file for every screen update.
    private nonisolated static func readTextFile(at url: URL)
        -> (content: String?, failure: (domain: String, code: Int, message: String)?, lines: Int) {
        var content: String?
        var failure: (domain: String, code: Int, message: String)?
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Error is not Sendable, so carry the parts needed to rebuild it.
            let ns = error as NSError
            failure = (ns.domain, ns.code, ns.localizedDescription)
            content = try? String(contentsOf: url, encoding: .isoLatin1)
        }
        let lines = content.map {
            $0.split(separator: "\n", omittingEmptySubsequences: false).count
        } ?? 0
        return (content, failure, lines)
    }

    /// Built at load and whenever the font settings change. It used to be a
    /// computed property, so every screen update rebuilt the whole string:
    /// 18 ms per update on a 10 MB file.
    private func rebuildTextAttributed() {
        guard isViewingText else { return }
        textFileAttributed = NSAttributedString(string: textFileContent, attributes: [
            .font: textViewFont,
            .foregroundColor: NSColor.textColor
        ])
    }

    /// On-screen font, scaled by the zoom slider. Printing and export keep
    /// the unscaled `textFileFont`, so zooming never changes paper output.
    private var textViewFont: NSFont {
        let scaled = max(6, textFileFont.pointSize * zoomLevel)
        return NSFont(descriptor: textFileFont.fontDescriptor, size: scaled) ?? textFileFont
    }

    private var textFileFont: NSFont {
        // "SF Mono" and the system font have no PostScript name NSFont(name:)
        // can resolve; they need the dedicated constructors.
        switch txtFontName {
        case "SF Mono":
            return .monospacedSystemFont(ofSize: txtFontSize, weight: .regular)
        case ".AppleSystemUIFont":
            return .systemFont(ofSize: txtFontSize)
        default:
            return NSFont(name: txtFontName, size: txtFontSize)
                ?? .monospacedSystemFont(ofSize: txtFontSize, weight: .regular)
        }
    }

    // MARK: - Open failures and sandbox permission recovery

    /// Cocoa 257 / POSIX EACCES mean the sandbox has no grant for this path
    /// (typically a Recent or reopen-at-launch file whose security-scoped
    /// bookmark is missing). Those get the Grant Access flow; anything else
    /// is a plain error alert.
    private func handleOpenFailure(url: URL, error: Error?) {
        finishLoad()
        let denied: Bool
        if let error {
            let ns = error as NSError
            let cocoaDenied = ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError
            let posixDenied = ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM))
            let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)
            let underlyingDenied = underlying.map { $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EACCES) || $0.code == Int(EPERM)) } ?? false
            denied = cocoaDenied || posixDenied || underlyingDenied
        } else {
            denied = FileManager.default.fileExists(atPath: url.path)
                && !FileManager.default.isReadableFile(atPath: url.path)
        }
        AppLog.write("Open FAILED \(url.path) denied=\(denied) error=\(error.map { String(describing: $0) } ?? "nil")")
        if denied {
            accessRequestURL = url
        } else if let error {
            errorAlertMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        } else {
            errorAlertMessage = "Could not open \(url.lastPathComponent). The file may be missing, unreadable, or not a valid PDF."
        }
    }

    /// Standard sandbox recovery: an open panel pointed at the file. The
    /// user's click is the grant; the resulting add() stores a bookmark so it
    /// never has to be asked again for this file.
    private func grantAccessAndReload(_ url: URL) {
        let panel = NSOpenPanel()
        panel.message = "Click Open to let MikePDFViewer read \(url.lastPathComponent). It will remember this file afterwards."
        panel.prompt = "Open"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        AppLog.write("Access granted via panel for \(chosen.path)")
        recentFiles.add(chosen)
        if OpenDocumentRegistry.key(for: chosen) == OpenDocumentRegistry.key(for: url) {
            // Same URL as pdfURL, so onChange would not fire; reload directly.
            loadDocument(from: chosen)
        } else {
            pdfURL = chosen
        }
    }

    // MARK: - Zoom

    /// Quick Look (PowerPoint, Keynote) and the Quick markdown view have no
    /// zoom of their own, so the control stays hidden there.
    private var canZoom: Bool {
        if pdfDocument != nil { return true }
        if isViewingMarkdown { return markdownMode == .reader }
        return isViewingText || isViewingHTML || isViewingSVG || isViewingImage || isViewingCSV
    }

    @ViewBuilder
    private var zoomOverlay: some View {
        if canZoom {
            ZoomControl(zoom: $zoomLevel) { value in applyZoom(value) }
                .padding(.trailing, 16)
                .padding(.bottom, 14)
                // Keep hits on the capsule only so the rest of the detail
                // pane still receives PDF text-selection drags.
                .contentShape(Capsule())
        }
    }

    /// Sends the slider value to whichever viewer is showing. Every mode
    /// treats 1.0 as the size the document opened at.
    private func applyZoom(_ value: Double) {
        if pdfDocument != nil {
            NotificationCenter.default.post(name: .pdfSetZoom, object: nil,
                                            userInfo: ["scale": value])
        } else if isViewingImage {
            imageViewer.setRelativeZoom(value)
        } else if isViewingSVG {
            htmlBrowser.svgSetScale(value)
        } else if isViewingHTML {
            htmlBrowser.setPageZoom(value)
        } else if isViewingMarkdown {
            mdSearch.webView?.pageZoom = CGFloat(value)
        } else if isViewingText {
            rebuildTextAttributed()
        }
        // CSV re-renders from the fontScale passed into CSVTableView.
    }

    /// Cmd+ and Cmd- reach the PDF view directly; every other mode is nudged
    /// through the same slider so the two stay in step.
    private func nudgeZoom(_ delta: Double) {
        guard canZoom, pdfDocument == nil else { return }
        zoomLevel = min(max(zoomLevel + delta, 0.25), 4.0)
        applyZoom(zoomLevel)
    }

    // MARK: - Export

    private var canExport: Bool {
        pdfDocument != nil || isViewingMarkdown || isViewingText || isViewingQuickLook
            || isViewingSVG || isViewingImage || isViewingCSV
    }

    private var exportStem: String {
        (openWithSourceURL ?? pdfURL)?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// File > Export and the toolbar Export menu. PDF and PNG go through a
    /// paginated PDF of the current view; Word comes from the text itself.
    private func exportDocument(_ format: ExportFormat) {
        guard canExport else { return }
        if isViewingQuickLook, originalDOCXURL == nil {
            errorAlertMessage = "Export isn't available for PowerPoint or Keynote files yet. Open the file in its own app to export it."
            return
        }
        // Verified twice against AppKit's Office Open XML writer: it drops
        // image attachments, so a Word export here would be an empty page.
        if format == .docx, isViewingImage {
            errorAlertMessage = "Word export can't carry a picture. Export as PDF or PNG instead, or paste the image into Word."
            return
        }
        switch format {
        case .docx:
            exportAsDOCX()
        case .pdf, .png:
            Task {
                do {
                    let pdf = try await exportablePDF()
                    if format == .pdf {
                        exportPDF(pdf)
                    } else {
                        exportImagesDocument = pdf
                        showExportImages = true
                    }
                } catch {
                    errorAlertMessage = "Could not prepare \(exportStem) for export: \(error.localizedDescription)"
                }
            }
        }
    }

    /// A paginated PDF of whatever is on screen, converting first when needed.
    private func exportablePDF() async throws -> PDFDocument {
        if let doc = pdfDocument { return doc }
        if isViewingMarkdown, let md = markdownDocument, let url = originalMarkdownURL {
            return try await MarkdownToPDFConverter.convertForPrint(
                source: md.source, sourceURL: url,
                theme: markdownTheme, typography: markdownTypography,
                marginInches: 0.5)
        }
        if isViewingText {
            let html = DocumentExporter.html(forPlainText: textFileContent, font: textFileFont)
            let data = try await PaginatedHTMLToPDF.render(html: html, marginInches: 0.5)
            guard let doc = PDFDocument(data: data), doc.pageCount > 0 else {
                throw MarkdownToPDFConverter.ConversionError.pdfRenderFailed
            }
            return doc
        }
        if isViewingImage, let picture = imageViewer.image {
            guard let page = PDFPage(image: picture) else {
                throw MarkdownToPDFConverter.ConversionError.pdfRenderFailed
            }
            let document = PDFDocument()
            document.insert(page, at: 0)
            return document
        }
        if isViewingCSV, let table = csvDocument {
            let html = DocumentExporter.html(forTable: table.columns, rows: table.rows,
                                             title: exportStem)
            let data = try await PaginatedHTMLToPDF.render(html: html, marginInches: 0.4)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                throw MarkdownToPDFConverter.ConversionError.pdfRenderFailed
            }
            return document
        }
        if isViewingSVG, let svgURL = originalSVGURL {
            let source = (try? String(contentsOf: svgURL, encoding: .utf8)) ?? ""
            let data = try await PaginatedHTMLToPDF.render(
                html: SVGPage.staticHTML(svgSource: source), marginInches: 0.5)
            guard let doc = PDFDocument(data: data), doc.pageCount > 0 else {
                throw MarkdownToPDFConverter.ConversionError.pdfRenderFailed
            }
            return doc
        }
        if let docxURL = originalDOCXURL {
            return try await DOCXToPDFConverter.convert(url: docxURL).document
        }
        throw MarkdownToPDFConverter.ConversionError.pdfRenderFailed
    }

    private func exportPDF(_ document: PDFDocument) {
        guard let url = DocumentExporter.chooseDestination(
            suggestedName: exportStem + ".pdf", type: .pdf, near: openWithSourceURL) else { return }
        if !document.write(to: url) {
            errorAlertMessage = "Could not write \(url.lastPathComponent). Check that the folder is writable."
        }
    }

    private func exportAsDOCX() {
        guard let docxType = UTType(filenameExtension: "docx"),
              let url = DocumentExporter.chooseDestination(
                suggestedName: exportStem + ".docx", type: docxType, near: openWithSourceURL) else { return }
        do {
            if let source = originalDOCXURL {
                // Already a Word file: hand over a copy. The save panel has
                // already asked about replacing an existing file.
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: source, to: url)
                return
            }
            let attributed: NSAttributedString
            if isViewingMarkdown, let md = markdownDocument {
                attributed = md.styledAttributedStringWithAnchors().0
            } else if isViewingCSV, let table = csvDocument {
                // Tab separated so Word lays the columns out on paste.
                let lines = ([table.columns] + table.rows)
                    .map { $0.joined(separator: "\t") }
                    .joined(separator: "\n")
                attributed = NSAttributedString(string: lines, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                ])
            } else if isViewingText {
                attributed = textFileAttributed
            } else if let pdf = pdfDocument {
                attributed = DocumentExporter.attributedString(from: pdf)
            } else {
                return
            }
            try DocumentExporter.writeDOCX(attributed, to: url)
        } catch {
            errorAlertMessage = "Could not export \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Printing

    /// Route Cmd+P / toolbar print to whichever viewer is active.
    private func handlePrint() {
        if pdfDocument != nil {
            PrintablePDFView.current?.performPrint()
        } else if isViewingMarkdown {
            printMarkdownDocument()
        } else if isViewingText {
            printTextDocument()
        } else if isViewingHTML || isViewingSVG {
            printHTMLDocument()
        } else if isViewingImage || isViewingCSV {
            printViaExportablePDF()
        } else if isViewingQuickLook {
            errorAlertMessage = "Printing isn't available in the quick viewer. Use Convert to PDF first, then print."
        }
    }

    private var canPrint: Bool {
        pdfDocument != nil || isViewingMarkdown || isViewingText || isViewingHTML
            || isViewingSVG || isViewingImage || isViewingCSV
    }

    /// Show the pre-print layout sheet (font size, margins, fit-to-pages,
    /// live paginated preview); the sheet hands back a paginated PDF that
    /// goes to the system print dialog.
    private func printMarkdownDocument() {
        guard markdownDocument != nil, originalMarkdownURL != nil else { return }
        showMarkdownPrintSheet = true
    }

    /// Modes with no printable view of their own (image, CSV) print the same
    /// PDF the export path builds.
    private func printViaExportablePDF() {
        Task {
            do {
                runPrintOperation(for: try await exportablePDF())
            } catch {
                errorAlertMessage = "Could not prepare \(exportStem) for printing: \(error.localizedDescription)"
            }
        }
    }

    private func runPrintOperation(for document: PDFDocument) {
        let printInfo = NSPrintInfo.shared
        guard let op = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) else {
            errorAlertMessage = "Could not create a print job for this document."
            return
        }
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// Print plain text (.txt/.log/.json) via a paginating NSTextView. Forces
    /// black-on-white so dark mode doesn't produce white-on-white pages.
    private func printTextDocument() {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let printable = NSAttributedString(string: textFileContent, attributes: [
            .font: textFileFont,
            .foregroundColor: NSColor.black
        ])
        let pageBounds = printInfo.imageablePageBounds
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageBounds.width, height: pageBounds.height))
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(printable)
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
            let height = max(pageBounds.height, layoutManager.usedRect(for: container).height)
            textView.frame = NSRect(x: 0, y: 0, width: pageBounds.width, height: height)
        }

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    private func printHTMLDocument() {
        let op = htmlBrowser.webView.printOperation(with: NSPrintInfo.shared)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // WKWebView print needs a nonzero view frame or it renders blank pages.
        op.view?.frame = htmlBrowser.webView.bounds
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    private func renderMarkdownAsPDF() {
        guard let doc = markdownDocument, let url = originalMarkdownURL else { return }
        isRenderingMarkdownPDF = true
        let generationAtStart = loadGeneration
        Task {
            do {
                let (pdfDoc, tempURL) = try await MarkdownToPDFConverter.convert(
                    source: doc.source,
                    sourceURL: url,
                    theme: markdownTheme,
                    typography: markdownTypography
                )
                await MainActor.run {
                    isRenderingMarkdownPDF = false
                    // Another file was opened while rendering - discard.
                    guard generationAtStart == loadGeneration,
                          originalMarkdownURL == url || pdfURL == url else { return }
                    pdfDocument = pdfDoc
                    pageState.totalPages = pdfDoc.pageCount
                    pageState.currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingMarkdown = false
                    markdownDocument = nil
                    markdownAttributed = nil
                    markdownAnchors = [:]
                    renderedPDFTempURL = tempURL
                    pendingRenderedSourceURL = url
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

    private func loadMarkdownDocument(from url: URL, generation: UInt64) {
        guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
        let wantsQuickView = markdownMode == .quick
        // Parse and render off the main thread; a mid-size file costs hundreds
        // of ms and used to beachball the whole open.
        Task.detached(priority: .userInitiated) {
            do {
                let doc = try MarkdownDocument(url: url)
                let (_, toc) = MarkdownToHTML.render(doc.source)
                let stats = ReadingStats(source: doc.source)
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    markdownTOC = toc
                    markdownStats = stats
                    isViewingMarkdown = true
                    originalMarkdownURL = url
                    markdownDocument = doc
                    // The attributed string is only used by Quick view; the
                    // default Reader never needs it, so it builds on demand
                    // (ensureMarkdownAttributed) instead of on every open.
                    markdownAttributed = nil
                    markdownAnchors = [:]
                    finishLoad()
                    if wantsQuickView { ensureMarkdownAttributed() }
                }
            } catch {
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                    handleOpenFailure(url: url, error: error)
                }
            }
        }
    }

    /// Build the Quick-view attributed string in the background if it hasn't
    /// been built for the current document yet.
    private func ensureMarkdownAttributed() {
        guard markdownAttributed == nil, let doc = markdownDocument,
              let url = originalMarkdownURL else { return }
        let generation = loadGeneration
        Task.detached(priority: .userInitiated) {
            let (styled, anchors) = doc.styledAttributedStringWithAnchors()
            await MainActor.run {
                guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                markdownAttributed = styled
                markdownAnchors = anchors
            }
        }
    }

    private func loadPDFDocument(from url: URL, generation: UInt64) {
        DispatchQueue.global(qos: .userInitiated).async {
            let doc = PDFDocument(url: url)
            let isLocked = doc?.isLocked ?? false
            let fields = isLocked ? 0 : Self.countFormFields(doc)
            DispatchQueue.main.async {
                guard acceptLoadIfCurrent(generation: generation, url: url) else { return }
                pdfDocument = doc
                pageState.totalPages = isLocked ? 0 : (doc?.pageCount ?? 0)
                pageState.currentPage = 0
                documentVersion = 0
                formFieldCount = fields
                bookmarkManager.load(for: url)
                finishLoad()
                if isLocked {
                    showPasswordSheet = true
                }
                if doc == nil {
                    handleOpenFailure(url: url, error: nil)
                }
            }
        }
    }

    private func loadDOCXDocument(from url: URL) {
        // Called from the "Convert to PDF" toolbar while already viewing the
        // file via Quick Look. Bump generation so a concurrent Open cannot
        // race this conversion onto the wrong window state.
        loadGeneration &+= 1
        let generation = loadGeneration
        isConvertingDOCX = true
        docxConversionError = nil
        originalDOCXURL = url
        isLoadingDocument = true
        // Keep Quick Look up until conversion finishes so the user is not
        // left on an empty pane for long DOCX converts.
        Task {
            do {
                let (doc, tempURL) = try await DOCXToPDFConverter.convert(url: url)
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: pdfURL ?? url) else {
                        isConvertingDOCX = false
                        return
                    }
                    // Prefer the live pdfURL if still this DOCX; fall back to
                    // the conversion source URL when pdfURL still points here.
                    let stillThisFile = (pdfURL == url) || (originalDOCXURL == url)
                    guard stillThisFile else {
                        isConvertingDOCX = false
                        finishLoad()
                        return
                    }
                    pdfDocument = doc
                    pageState.totalPages = doc.pageCount
                    pageState.currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingDOCX = true
                    docxTempPDFURL = tempURL
                    isViewingQuickLook = false
                    quickLookURL = nil
                    isViewingMarkdown = false
                    isViewingEML = false
                    isViewingText = false
                    isViewingHTML = false
                    bookmarkManager.load(for: url)
                    isConvertingDOCX = false
                    finishLoad()
                }
            } catch {
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: pdfURL ?? url) else {
                        isConvertingDOCX = false
                        return
                    }
                    docxConversionError = error.localizedDescription
                    errorAlertMessage = "Could not convert \(url.lastPathComponent) to PDF: \(error.localizedDescription)"
                    isConvertingDOCX = false
                    finishLoad()
                }
            }
        }
    }

    private func loadEMLDocument(from url: URL, generation: UInt64) {
        isConvertingEML = true
        emlConversionError = nil
        originalEMLURL = url
        let loadExternal = loadExternalImages
        // Read + parse off the main actor; convert hops back because the
        // converter is @MainActor (WKWebView).
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let message = try EMLParser.parse(data: data)
                let doc = try await EMLToPDFConverter.convert(message, loadExternalImages: loadExternal)
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else {
                        isConvertingEML = false
                        return
                    }
                    pdfDocument = doc
                    pageState.totalPages = doc.pageCount
                    pageState.currentPage = 0
                    documentVersion = 0
                    formFieldCount = 0
                    isViewingEML = true
                    emlMessage = message
                    emlAttachments = message.attachments
                    originalEMLURL = url
                    bookmarkManager.load(for: url)
                    isConvertingEML = false
                    finishLoad()
                }
            } catch {
                await MainActor.run {
                    guard acceptLoadIfCurrent(generation: generation, url: url) else {
                        isConvertingEML = false
                        return
                    }
                    emlConversionError = error.localizedDescription
                    errorAlertMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
                    isConvertingEML = false
                    finishLoad()
                    pdfDocument = nil
                    pageState.totalPages = 0
                }
            }
        }
    }

    private func reloadEML() {
        guard let url = originalEMLURL else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        // Keep pdfURL pointing at the EML; clear PDF surface then reconvert.
        pdfDocument = nil
        pageState.totalPages = 0
        isLoadingDocument = true
        loadEMLDocument(from: url, generation: generation)
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

// MARK: - Find commands listener
// Separate ViewModifier so the giant `viewWithNotifications` body doesn't
// blow past the Swift type-checker's complexity budget.

struct FindCommandsListener: ViewModifier {
    let onShowFind: () -> Void
    let onFindNext: () -> Void
    let onFindPrev: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .pdfShowFind)) { _ in onShowFind() }
            .onReceive(NotificationCenter.default.publisher(for: .pdfFindNext)) { _ in onFindNext() }
            .onReceive(NotificationCenter.default.publisher(for: .pdfFindPrev)) { _ in onFindPrev() }
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

// MARK: - Zoom commands

/// Cmd+ and Cmd- for the non-PDF viewers. Kept out of the main view's chain,
/// which is already at the Swift type-checker's limit.
private struct ZoomCommandsListener: ViewModifier {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .pdfZoomIn)) { _ in onZoomIn() }
            .onReceive(NotificationCenter.default.publisher(for: .pdfZoomOut)) { _ in onZoomOut() }
    }
}

// MARK: - Text font changes

/// Two onChange modifiers inline pushed the main view past the Swift
/// type-checker's budget, so they live here as one.
private struct TextFontChangeListener: ViewModifier {
    let fontName: String
    let fontSize: Double
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: fontName) { _, _ in onChange() }
            .onChange(of: fontSize) { _, _ in onChange() }
    }
}

// MARK: - Permission Needed alert

/// Separate modifier so the giant body chain stays type-checkable.
private struct AccessRequestAlert: ViewModifier {
    @Binding var url: URL?
    let onGrant: (URL) -> Void

    func body(content: Content) -> some View {
        content.alert("Permission Needed",
                      isPresented: Binding(get: { url != nil },
                                           set: { if !$0 { url = nil } })) {
            Button("Grant Access…") {
                if let target = url {
                    url = nil
                    DispatchQueue.main.async { onGrant(target) }
                }
            }
            Button("Cancel", role: .cancel) { url = nil }
        } message: {
            Text("macOS hasn't let MikePDFViewer read \(url?.lastPathComponent ?? "this file") since the app was last launched. Click Grant Access, then Open in the panel, and the app will remember it.")
        }
    }
}

// MARK: - Page-state isolation helpers
// These child views observe DocumentPageState. ContentView only passes the
// object through, so PDF scroll page changes do not rebuild the toolbar tree.

private struct BoundPDFKitView: View {
    let document: PDFDocument
    @Bindable var pageState: DocumentPageState
    let searchText: String
    let darkMode: Bool
    let displayMode: PDFDisplayMode

    var body: some View {
        PDFKitView(
            document: document,
            currentPage: $pageState.currentPage,
            searchText: searchText,
            darkMode: darkMode,
            displayMode: displayMode
        )
    }
}

private struct BoundThumbnailSidebar: View {
    let document: PDFDocument
    @Bindable var pageState: DocumentPageState
    let documentVersion: Int
    @ObservedObject var bookmarkManager: BookmarkManager
    var onMovePage: ((Int, Int) -> Void)?
    var onDeletePages: (([Int]) -> Void)?

    var body: some View {
        ThumbnailSidebar(
            document: document,
            currentPage: $pageState.currentPage,
            totalPages: pageState.totalPages,
            documentVersion: documentVersion,
            bookmarkManager: bookmarkManager,
            onMovePage: onMovePage,
            onDeletePages: onDeletePages
        )
    }
}

private struct PageStatusControl: View {
    @Bindable var pageState: DocumentPageState
    @Binding var showGoToPage: Bool
    @Binding var goToPageText: String
    let onNavigate: () -> Void

    var body: some View {
        if pageState.totalPages > 0 {
            Button {
                goToPageText = ""
                showGoToPage = true
            } label: {
                Text("Page \(pageState.currentPage + 1) of \(pageState.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .tooltip("Go to Page (Cmd+Option+G)")
            .popover(isPresented: $showGoToPage) {
                VStack(spacing: 12) {
                    Text("Go to Page")
                        .font(.headline)
                    HStack {
                        TextField("Page number", text: $goToPageText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit { onNavigate() }
                        Text("of \(pageState.totalPages)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Cancel") { showGoToPage = false }
                            .keyboardShortcut(.cancelAction)
                        Button("Go") { onNavigate() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(Int(goToPageText) == nil)
                    }
                }
                .padding()
            }
        }
    }
}

private struct BookmarkToolbarButton: View {
    @Bindable var pageState: DocumentPageState
    @ObservedObject var bookmarkManager: BookmarkManager
    let enabled: Bool

    var body: some View {
        Button { bookmarkManager.toggleBookmark(for: pageState.currentPage) } label: {
            Image(systemName: bookmarkManager.isBookmarked(pageState.currentPage) ? "bookmark.fill" : "bookmark")
        }
        .tooltip("Toggle Bookmark (Cmd+D)")
        .disabled(!enabled)
    }
}

// MARK: - Tooltips that survive .disabled

/// SwiftUI's .help() tooltip does not appear while the control is disabled
/// (e.g. the PDF-only toolbar icons when a markdown/text file is open). An
/// AppKit toolTip on a backing NSView keeps working either way, so toolbar
/// buttons use this instead.
private struct TooltipBackground: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    /// Drop-in replacement for .help() that still shows when disabled.
    func tooltip(_ text: String) -> some View {
        background(TooltipBackground(text: text))
    }
}

#Preview {
    ContentView()
        .environmentObject(RecentFilesManager())
}
