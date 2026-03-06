import SwiftUI

@main
struct MikePDFViewerApp: App {
    @StateObject private var recentFiles = RecentFilesManager()
    @State private var pdfURL: URL?
    @State private var showMergeView = false

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
}
