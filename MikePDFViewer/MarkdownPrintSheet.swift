import SwiftUI
import PDFKit

/// Read-only PDFView wrapper for the print preview pane (no annotations,
/// no notifications; the main viewer's PDFKitView is deliberately not reused).
private struct PrintPreviewPDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}

/// Pre-print options for markdown files: a live paginated preview with font
/// size, margin, and fit-to-N-pages controls, shown before the system print
/// dialog. Exists because long documents used to print as one giant
/// shrunk-to-fit page.
struct MarkdownPrintSheet: View {
    let source: String
    let sourceURL: URL
    let theme: MarkdownReaderTheme
    let baseTypography: MarkdownTypography
    let onPrint: (PDFDocument) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum MarginChoice: String, CaseIterable, Identifiable {
        case narrow, normal, wide
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .narrow: return "Narrow (0.3 in)"
            case .normal: return "Normal (0.5 in)"
            case .wide:   return "Wide (1 in)"
            }
        }
        var inches: Double {
            switch self {
            case .narrow: return 0.3
            case .normal: return 0.5
            case .wide:   return 1.0
            }
        }
    }

    @AppStorage("md-print-font-size") private var fontSize: Int = 12
    @AppStorage("md-print-margin") private var marginRaw: String = MarginChoice.normal.rawValue
    @State private var fitToPages: Bool = false
    @State private var targetPages: Int = 2
    @State private var preview: PDFDocument?
    @State private var appliedZoom: Double = 1.0
    @State private var isRendering: Bool = false
    @State private var renderGeneration: Int = 0
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                previewPane
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                controls
                    .frame(width: 250)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .onAppear { rerender() }
        .onChange(of: fontSize) { _, _ in rerender() }
        .onChange(of: marginRaw) { _, _ in rerender() }
        .onChange(of: fitToPages) { _, _ in rerender() }
        .onChange(of: targetPages) { _, _ in rerender() }
    }

    @ViewBuilder
    private var previewPane: some View {
        ZStack {
            if let preview {
                PrintPreviewPDFView(document: preview)
                    .id(ObjectIdentifier(preview))
            }
            if isRendering {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.regularMaterial)
                .cornerRadius(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Print Layout")
                .font(.headline)

            Stepper("Font size: \(fontSize) pt", value: $fontSize, in: 8...24)

            Picker("Margins", selection: $marginRaw) {
                ForEach(MarginChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            Toggle("Fit to a page limit", isOn: $fitToPages)
            Stepper("At most \(targetPages) page\(targetPages == 1 ? "" : "s")",
                    value: $targetPages, in: 1...20)
                .disabled(!fitToPages)
            Text("Fit shrinks the text (down to 35%) until the document fits the page limit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let preview, !isRendering {
                Text(statusText(for: preview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Print…") {
                if let preview {
                    dismiss()
                    onPrint(preview)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(preview == nil || isRendering)
        }
        .padding(12)
    }

    private func statusText(for document: PDFDocument) -> String {
        var text = "\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")"
        if appliedZoom < 0.999 {
            text += ", text scaled to \(Int((appliedZoom * 100).rounded()))%"
        }
        return text
    }

    private func rerender() {
        renderGeneration += 1
        let generation = renderGeneration
        isRendering = true
        errorText = nil

        var typography = baseTypography
        typography.fontSize = fontSize
        let margin = MarginChoice(rawValue: marginRaw)?.inches ?? 0.5
        let target: Int? = fitToPages ? targetPages : nil

        Task {
            do {
                func render(zoom: Double) async throws -> PDFDocument {
                    try await MarkdownToPDFConverter.convertForPrint(
                        source: source,
                        sourceURL: sourceURL,
                        theme: theme,
                        typography: typography,
                        marginInches: margin,
                        zoom: zoom)
                }

                var zoom = 1.0
                var document = try await render(zoom: zoom)
                guard generation == renderGeneration else { return }

                if let target, document.pageCount > target {
                    // Binary-search the largest zoom that still fits.
                    var low = 0.35, high = 1.0
                    var best: (PDFDocument, Double)?
                    for _ in 0..<5 {
                        let mid = (low + high) / 2
                        let candidate = try await render(zoom: mid)
                        guard generation == renderGeneration else { return }
                        if candidate.pageCount <= target {
                            best = (candidate, mid)
                            low = mid
                        } else {
                            high = mid
                        }
                    }
                    if let best {
                        document = best.0
                        zoom = best.1
                    } else {
                        document = try await render(zoom: 0.35)
                        zoom = 0.35
                        guard generation == renderGeneration else { return }
                        errorText = "Doesn't fit in \(target) page\(target == 1 ? "" : "s") even at 35%; showing smallest."
                    }
                }

                preview = document
                appliedZoom = zoom
                isRendering = false
            } catch {
                guard generation == renderGeneration else { return }
                isRendering = false
                errorText = "Preview failed: \(error.localizedDescription)"
            }
        }
    }
}
