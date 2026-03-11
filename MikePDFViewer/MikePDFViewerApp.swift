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

extension FocusedValues {
    var pdfDocument: PDFDocument? {
        get { self[FocusedPDFDocumentKey.self] }
        set { self[FocusedPDFDocumentKey.self] = newValue }
    }
    var pdfFileURL: URL? {
        get { self[FocusedPDFURLKey.self] }
        set { self[FocusedPDFURLKey.self] = newValue }
    }
}

@main
struct MikePDFViewerApp: App {
    @StateObject private var recentFiles = RecentFilesManager()
    @State private var pdfURL: URL?
    @State private var showMergeView = false
    @FocusedValue(\.pdfDocument) var focusedDocument
    @FocusedValue(\.pdfFileURL) var focusedURL

    var body: some Scene {
        WindowGroup {
            ContentView(pdfURL: $pdfURL)
                .environmentObject(recentFiles)
                .onOpenURL { url in
                    recentFiles.add(url)
                    pdfURL = url
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF...") {
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

                Button("Merge PDFs...") {
                    showMergeView = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Menu("Recent PDFs") {
                    if recentFiles.recentURLs.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(recentFiles.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                pdfURL = url
                            }
                        }
                        Divider()
                        Button("Clear Recent") {
                            recentFiles.clear()
                        }
                    }
                }
            }

            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    printDocument()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(focusedDocument == nil)
            }

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
            }
        }

        Window("Merge PDFs", id: "merge") {
            PDFMergeView()
        }
        .defaultSize(width: 900, height: 600)
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

    private func printDocument() {
        guard let document = focusedDocument else { return }
        let printInfo = NSPrintInfo.shared
        if let printOperation = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) {
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true
            printOperation.run()
        }
    }
}
