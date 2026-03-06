import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Binding var pdfURL: URL?

    var body: some View {
        Group {
            if let pdfURL {
                PDFKitView(url: pdfURL)
            } else {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openPDF()
                } label: {
                    Image(systemName: "folder")
                }
            }
        }
    }

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            pdfURL = url
        }
    }
}

#Preview {
    ContentView(pdfURL: .constant(nil))
}
