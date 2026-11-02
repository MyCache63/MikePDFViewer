import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ExportImagesView: View {
    let document: PDFDocument
    /// Source file name without its extension; every exported image starts with it.
    var baseName: String = "Untitled"
    /// Folder the picker opens in: the source file's own folder.
    var startFolder: URL? = nil
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
        panel.directoryURL = startFolder
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        error = ""

        let start = max(startPage - 1, 0)
        let end = min(endPage, document.pageCount)
        let total = end - start
        let dpiValue = CGFloat(dpi)
        let imageFormat = format
        let names = Self.fileNames(base: baseName, pages: start..<end,
                                   ext: format == .png ? "png" : "jpg", in: folder)

        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            for i in start..<end {
                guard let page = document.page(at: i) else { continue }

                let data: Data?
                switch imageFormat {
                case .png:  data = PageRenderer.renderPageToPNG(page, dpi: dpiValue)
                case .jpeg: data = PageRenderer.renderPageToJPEG(page, dpi: dpiValue)
                }

                let fileURL = folder.appendingPathComponent(names[i - start])
                do {
                    guard let data else { throw CocoaError(.fileWriteUnknown) }
                    // withoutOverwriting: an existing file is never replaced.
                    try data.write(to: fileURL, options: .withoutOverwriting)
                    AppLog.write("export image: wrote \(fileURL.lastPathComponent)")
                } catch {
                    failures.append(fileURL.lastPathComponent)
                    AppLog.write("export image: FAILED \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }

                DispatchQueue.main.async {
                    progress = Double(i - start + 1) / Double(total)
                }
            }

            DispatchQueue.main.async {
                isExporting = false
                if failures.isEmpty {
                    dismiss()
                } else {
                    error = "Couldn't write \(failures.count) image(s): \(failures.prefix(3).joined(separator: ", "))"
                }
            }
        }
    }

    /// "<source>_2026-11-02_14-32-07.53.png", plus "_p03" when more than one
    /// page is exported. A prior export used plain "page_0001.png" and replaced
    /// whatever was already in the folder (2 Nov 2026). Colons aren't allowed
    /// in Finder names, so the time uses dashes. If a name is somehow taken, a
    /// counter is added; nothing is ever overwritten.
    static func fileNames(base: String, pages: Range<Int>, ext: String, in folder: URL) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss.SS"
        let stamp = formatter.string(from: Date())
        let digits = max(2, String(pages.upperBound).count)
        return pages.map { index in
            var stem = "\(base)_\(stamp)"
            if pages.count > 1 {
                stem += "_p" + String(format: "%0\(digits)d", index + 1)
            }
            var name = "\(stem).\(ext)"
            var counter = 2
            while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                name = "\(stem)-\(counter).\(ext)"
                counter += 1
            }
            return name
        }
    }
}
