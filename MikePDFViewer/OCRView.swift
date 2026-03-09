import SwiftUI
import PDFKit

struct OCRView: View {
    let document: PDFDocument
    @StateObject private var ocrService = OCRService()
    @State private var showAPIKeySheet = false
    @State private var apiKeyInput = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("OCR Document")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if !ocrService.isProcessing {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape)
                }
            }
            .padding()

            Divider()

            if ocrService.results.isEmpty && !ocrService.isProcessing {
                // Initial state - ready to start
                startView
            } else if ocrService.isProcessing {
                // Processing
                progressView
            } else {
                // Results
                resultsView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showAPIKeySheet) {
            apiKeySheet
        }
        .onAppear {
            apiKeyInput = ocrService.apiKey
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("OCR with AI Vision")
                .font(.title3)
            Text("\(document.pageCount) pages will be sent to Claude Sonnet for high-accuracy text extraction.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let error = ocrService.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Set API Key") {
                    showAPIKeySheet = true
                }
                .buttonStyle(.bordered)

                Button("Start OCR") {
                    startOCR()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ocrService.hasAPIKey)
            }

            if ocrService.hasAPIKey {
                Text("Using OpenRouter API")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("OpenRouter API key required")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding()
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: ocrService.progress) {
                Text(ocrService.statusText)
            }
            .frame(maxWidth: 400)

            Text("This may take a minute for large documents...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(ocrService.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    copyAllText()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    saveAsText()
                } label: {
                    Label("Save Text", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    saveAsDOCX()
                } label: {
                    Label("Save DOCX", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Text results
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ocrService.results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Page \(result.pageNumber)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                if result.isCoverPage {
                                    Text("Cover")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                Spacer()
                            }
                            Text(result.text)
                                .font(.system(.body, design: .serif))
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }

    private var apiKeySheet: some View {
        VStack(spacing: 16) {
            Text("OpenRouter API Key")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter your OpenRouter API key for OCR processing. Get one at openrouter.ai")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("sk-or-v1-...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)

            HStack {
                Button("Cancel") {
                    showAPIKeySheet = false
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    ocrService.apiKey = apiKeyInput
                    showAPIKeySheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(apiKeyInput.isEmpty)
            }
        }
        .padding(30)
    }

    private func startOCR() {
        guard ocrService.hasAPIKey else {
            showAPIKeySheet = true
            return
        }
        Task {
            await ocrService.processDocument(document)
        }
    }

    private func copyAllText() {
        let allText = ocrService.results.map { $0.text }.joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
    }

    private func saveAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ocr_output.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let allText = ocrService.results.map {
            "--- Page \($0.pageNumber) ---\n\n\($0.text)"
        }.joined(separator: "\n\n")

        try? allText.write(to: url, atomically: true, encoding: .utf8)
    }

    private func saveAsDOCX() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
        panel.nameFieldStringValue = "ocr_output.docx"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try DOCXExporter.export(pages: ocrService.results)
            try data.write(to: url)
        } catch {
            ocrService.errorMessage = "DOCX export failed: \(error.localizedDescription)"
        }
    }
}
