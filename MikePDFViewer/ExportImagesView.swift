import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ExportImagesView: View {
    let document: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format: ImageFormat = .png
    @State private var dpi: Double = 150
    @State private var startPage = 1
    @State private var endPage = 1
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var error = ""

    enum ImageFormat: String, CaseIterable {
        case png = "PNG"
        case jpeg = "JPEG"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Pages as Images")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Format:")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $format) {
                        ForEach(ImageFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack {
                    Text("DPI:")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $dpi) {
                        Text("72 (Screen)").tag(72.0)
                        Text("150 (Medium)").tag(150.0)
                        Text("300 (Print)").tag(300.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                HStack {
                    Text("Pages:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("From", value: $startPage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("to")
                    TextField("To", value: $endPage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("of \(document.pageCount)")
                        .foregroundStyle(.secondary)
                }
            }

            if isExporting {
                ProgressView(value: progress)
                    .frame(width: 300)
                Text("Exporting page \(Int(progress * Double(endPage - startPage + 1)) + startPage) of \(endPage)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export") { exportImages() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || startPage < 1 || endPage > document.pageCount || startPage > endPage)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
        .onAppear {
            endPage = document.pageCount
        }
    }

    private func exportImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        error = ""

        let start = max(startPage - 1, 0)
        let end = min(endPage, document.pageCount)
        let total = end - start
        let dpiValue = CGFloat(dpi)
        let imageFormat = format

        DispatchQueue.global(qos: .userInitiated).async {
            for i in start..<end {
                guard let page = document.page(at: i) else { continue }

                let data: Data?
                let ext: String
                switch imageFormat {
                case .png:
                    data = PageRenderer.renderPageToPNG(page, dpi: dpiValue)
                    ext = "png"
                case .jpeg:
                    data = PageRenderer.renderPageToJPEG(page, dpi: dpiValue)
                    ext = "jpg"
                }

                if let data {
                    let filename = "page_\(String(format: "%04d", i + 1)).\(ext)"
                    let fileURL = folder.appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                }

                DispatchQueue.main.async {
                    progress = Double(i - start + 1) / Double(total)
                }
            }

            DispatchQueue.main.async {
                isExporting = false
                dismiss()
            }
        }
    }
}
