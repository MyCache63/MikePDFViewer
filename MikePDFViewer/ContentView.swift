import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var pdfURL: URL?
    @State private var showFilePicker = false

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
                        showFilePicker = true
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
                    showFilePicker = true
                } label: {
                    Image(systemName: "folder")
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        pdfURL = url
                    }
                }
            case .failure(let error):
                print("File picker error: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView(pdfURL: .constant(nil))
}
