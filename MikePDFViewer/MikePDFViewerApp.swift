import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Focused Value Keys

struct FocusedPDFDocumentKey: FocusedValueKey {
    typealias Value = PDFDocument
}

struct FocusedPDFURLKey: FocusedValueKey {
    typealias Value = URL
}

struct FocusedDarkModeKey: FocusedValueKey {
    typealias Value = Bool
}

struct FocusedDisplayModeKey: FocusedValueKey {
    typealias Value = Int
}

extension FocusedValues {
    var pdfDocument: PDFDocument? {
        get { self[FocusedPDFDocumentKey.self] }
        set { self[FocusedPDFDocumentKey.self] = newValue }
    }
    var pdfFileURL: URL? {
        get { self[FocusedPDFURLKey.self] }
        set { self[FocusedPDFURLKey.self] = newValue }
    }
    var isDarkMode: Bool? {
        get { self[FocusedDarkModeKey.self] }
        set { self[FocusedDarkModeKey.self] = newValue }
    }
    var displayModeRawValue: Int? {
        get { self[FocusedDisplayModeKey.self] }
        set { self[FocusedDisplayModeKey.self] = newValue }
    }
}

// MARK: - App

@main
struct MikePDFViewerApp: App {
    @StateObject private var recentFiles = RecentFilesManager()
    @FocusedValue(\.pdfDocument) var focusedDocument
    @FocusedValue(\.pdfFileURL) var focusedURL
    @FocusedValue(\.isDarkMode) var isDarkMode
    @FocusedValue(\.displayModeRawValue) var displayModeRaw

    init() {
        // Standalone app uses ~/Documents/MikePDFViewer/tmp (sandboxing maps
        // this to the container). The kit's default for embedding hosts is
        // NSTemporaryDirectory/MikePDFViewerKit/. Set the standalone path
        // here so behavior matches v5.x for users who already have files
        // staged in the container Documents folder.
        TempFolderManager.baseDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MikePDFViewer", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
        TempFolderManager.purgeOldFiles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recentFiles)
        }
        .commands {
            // MARK: File Menu
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    openPDF()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Save") {
                    saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(focusedDocument == nil)

                Button("Save As...") {
                    saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(focusedDocument == nil)

                Divider()

                Menu("Open With") {
                    if let url = focusedURL {
                        let kind = OpenWithFileKind.detect(url: url)
                        let apps = OpenWithHelpers.curatedApps(for: kind)
                        ForEach(apps, id: \.self) { app in
                            Button(OpenWithHelpers.displayName(for: app)) {
                                OpenWithHelpers.openIn(app: app, file: url)
                            }
                        }
                        if !apps.isEmpty {
                            Divider()
                        }
                        Button("Other…") {
                            OpenWithHelpers.showOtherPicker(file: url)
                        }
                    } else {
                        Text("No file open")
                    }
                }

                Divider()

                Button("Merge PDFs...") {
                    NotificationCenter.default.post(name: .pdfShowMerge, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Menu("Recent PDFs") {
                    if recentFiles.recentURLs.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(recentFiles.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(name: .pdfOpenFile, object: nil, userInfo: ["url": url])
                            }
                        }
                        Divider()
                        Button("Clear Recent") {
                            recentFiles.clear()
                        }
                    }
                }
            }

            // MARK: Edit Menu
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Copy Selection") {
                    NotificationCenter.default.post(name: .pdfCopy, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(focusedDocument == nil)
            }

            // MARK: Print
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    PrintablePDFView.current?.performPrint()
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // MARK: Tools Menu
            CommandMenu("Tools") {
                Button("Toggle Bookmark") {
                    NotificationCenter.default.post(name: .pdfToggleBookmark, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(focusedDocument == nil)

                Button("Extract Pages...") {
                    NotificationCenter.default.post(name: .pdfExtractPages, object: nil)
                }
                .disabled(focusedDocument == nil)

                Divider()

                Button("Clear Rendered Temp Files") {
                    TempFolderManager.clearAll()
                }
            }

            // MARK: View Menu
            CommandGroup(after: .toolbar) {
                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .pdfZoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(focusedDocument == nil)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .pdfZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(focusedDocument == nil)

                Button("Zoom to Fit") {
                    NotificationCenter.default.post(name: .pdfZoomFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(focusedDocument == nil)

                Divider()

                Button(isDarkMode == true ? "Light Reading Mode" : "Dark Reading Mode") {
                    NotificationCenter.default.post(name: .pdfToggleDarkMode, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(focusedDocument == nil)

                Divider()

                Menu("Display Mode") {
                    Button("Continuous Scroll") {
                        setDisplayMode(.singlePageContinuous)
                    }
                    Button("Single Page") {
                        setDisplayMode(.singlePage)
                    }
                    Button("Two Pages") {
                        setDisplayMode(.twoUp)
                    }
                    Button("Two Pages Scroll") {
                        setDisplayMode(.twoUpContinuous)
                    }
                }
                .disabled(focusedDocument == nil)

                Divider()

                Button("Rotate Right") {
                    NotificationCenter.default.post(name: .pdfRotateRight, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(focusedDocument == nil)

                Button("Rotate Left") {
                    NotificationCenter.default.post(name: .pdfRotateLeft, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(focusedDocument == nil)

                Divider()

                Button("Split View") {
                    NotificationCenter.default.post(name: .pdfToggleSplitView, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(focusedDocument == nil)

                Button("Presentation Mode") {
                    NotificationCenter.default.post(name: .pdfStartPresentation, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(focusedDocument == nil)
            }
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
            NotificationCenter.default.post(name: .pdfOpenFile, object: nil, userInfo: ["url": url])
        }
    }

    private func saveDocument() {
        guard let document = focusedDocument, let url = focusedURL else { return }
        document.write(to: url)
    }

    private func saveDocumentAs() {
        guard let document = focusedDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = focusedURL?.lastPathComponent ?? "Untitled.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            document.write(to: url)
        }
    }

    private func setDisplayMode(_ mode: PDFDisplayMode) {
        NotificationCenter.default.post(
            name: .pdfSetDisplayMode,
            object: nil,
            userInfo: ["mode": mode.rawValue]
        )
    }
}
