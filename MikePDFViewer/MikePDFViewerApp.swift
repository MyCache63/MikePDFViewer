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

// MARK: - App Delegate (quit protection)

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Kept current by ContentView whenever its dirty flag changes.
    static var hasUnsavedChanges = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "The open document has unsaved edits (annotations, OCR, or page changes). Cancel and press Cmd+S to keep them, or quit and lose them."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

// MARK: - App

@main
struct MikePDFViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recentFiles = RecentFilesManager()
    @AppStorage("reopenLastDocument") private var reopenLastDocument = true
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
                                // Resolve the security-scoped bookmark so the
                                // sandbox lets us read the file after relaunch.
                                let resolved = recentFiles.beginAccess(url)
                                NotificationCenter.default.post(name: .pdfOpenFile, object: nil, userInfo: ["url": resolved])
                            }
                        }
                        Divider()
                        Button("Clear Recent") {
                            recentFiles.clear()
                        }
                    }
                }

                Divider()

                Toggle("Reopen Last File on Launch", isOn: $reopenLastDocument)
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

            // MARK: Find Menu (Edit → Find ▸ Find…)
            // Lives in its own CommandGroup so it surfaces in the Edit menu
            // and registers Cmd+F as a real menu shortcut (the prior
            // implementation relied on a hidden NSView keyDown override,
            // which broke when the WKWebView/NSTextView grabbed focus).
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    NotificationCenter.default.post(name: .pdfShowFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .pdfFindNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .pdfFindPrev, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
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

                Button("Make Searchable (OCR)") {
                    NotificationCenter.default.post(name: .pdfMakeSearchable, object: nil)
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

                // Cmd+G belongs to Find Next per macOS convention, so Go to
                // Page gets Preview's shortcut, Cmd+Option+G.
                Button("Go to Page...") {
                    NotificationCenter.default.post(name: .pdfGoToPage, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(focusedDocument == nil)

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
        var types: [UTType] = [.pdf, .plainText]
        if let emlType = UTType(filenameExtension: "eml") { types.append(emlType) }
        if let docxType = UTType(filenameExtension: "docx") { types.append(docxType) }
        if let mdType = UTType(filenameExtension: "md") { types.append(mdType) }
        if let logType = UTType(filenameExtension: "log") { types.append(logType) }
        if let pptxType = UTType(filenameExtension: "pptx") { types.append(pptxType) }
        if let pptType = UTType(filenameExtension: "ppt") { types.append(pptType) }
        if let keyType = UTType(filenameExtension: "key") { types.append(keyType) }
        types.append(.html)
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            recentFiles.add(url)
            NotificationCenter.default.post(name: .pdfOpenFile, object: nil, userInfo: ["url": url])
        }
    }

    private func saveDocument() {
        guard let document = focusedDocument, let url = focusedURL else { return }
        // In-place save is only safe when the opened file really is a PDF.
        // For converted sources (.docx/.eml/.md) the in-memory document is a
        // rendered PDF but the URL still points at the ORIGINAL file; writing
        // there would overwrite a Word doc / email with PDF bytes.
        guard url.pathExtension.lowercased() == "pdf" else {
            saveDocumentAs()
            return
        }
        writeDocument(document, to: url)
    }

    private func saveDocumentAs() {
        guard let document = focusedDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let stem = focusedURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = stem + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            writeDocument(document, to: url)
        }
    }

    private func writeDocument(_ document: PDFDocument, to url: URL) {
        if document.write(to: url) {
            NotificationCenter.default.post(name: .pdfDocumentSaved, object: document)
        } else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Save Failed"
            alert.informativeText = "Could not write to \(url.path). Check that the location is writable and the disk has space, then try Save As."
            alert.runModal()
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
