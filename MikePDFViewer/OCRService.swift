import SwiftUI
import PDFKit

struct OCRPageResult: Identifiable {
    let id = UUID()
    let pageNumber: Int
    let text: String
    let isCoverPage: Bool
}

class OCRService: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var results: [OCRPageResult] = []
    @Published var errorMessage: String?

    private let apiBaseURL = "https://openrouter.ai/api/v1/chat/completions"
    private let model = "anthropic/claude-sonnet-4"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "openRouterAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openRouterAPIKey") }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    private let ocrPrompt = """
    You are a high-accuracy OCR system. Transcribe ALL text from this scanned document page.

    Rules:
    1. Detect whether the page is single-column or multi-column layout.
    2. For multi-column pages: read the LEFT column completely (top to bottom), then the RIGHT column completely (top to bottom).
    3. Preserve paragraph structure. Join hyphenated words that are split across lines (e.g., "devel-\\nopment" → "development").
    4. Preserve superscript reference numbers by writing them as [1], [2], etc.
    5. For mathematical symbols, use Unicode where possible (e.g., τ, σ, ε, φ, π, ², ³).
    6. Mark section headings with ## (markdown heading level 2).
    7. Output ONLY the transcribed text. No commentary, no descriptions of images or figures.
    8. If there are figures or diagrams, note them as [Figure X] on their own line.
    9. Be extremely accurate — every word matters.
    10. FOOTNOTES: Any text at the bottom of a column that is a footnote, author affiliation note, or annotation (often marked with *, †, ‡, or superscript numbers, and visually separated from body text by a line or whitespace) must be extracted separately. Place all footnotes at the END of the page output, each on its own line prefixed with [Footnote]: — for example: [Footnote]: *Member AIAA
    11. PAGE NUMBERS: Do NOT include standalone page numbers (like "1", "2", "3" at the bottom of the page) in the output. Omit them entirely.
    """

    func processDocument(_ document: PDFDocument) async {
        await MainActor.run {
            isProcessing = true
            progress = 0
            results = []
            errorMessage = nil
            statusText = "Starting OCR..."
        }

        let pageCount = document.pageCount
        var pageResults: [OCRPageResult] = []

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }

            await MainActor.run {
                statusText = "Processing page \(i + 1) of \(pageCount)..."
                progress = Double(i) / Double(pageCount)
            }

            do {
                let text = try await ocrPage(page)
                let isCover = (i == 0) && looksLikeCoverPage(text)
                let result = OCRPageResult(pageNumber: i + 1, text: text, isCoverPage: isCover)
                pageResults.append(result)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed on page \(i + 1): \(error.localizedDescription)"
                }
                break
            }
        }

        let finalResults = pageResults
        let count = finalResults.count
        await MainActor.run {
            results = finalResults
            progress = 1.0
            isProcessing = false
            statusText = "Done — \(count) pages processed"
        }
    }

    private func looksLikeCoverPage(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Cover pages are typically short and don't have ## section headings in the body
        let hasAbstract = text.contains("## Abstract")
        let hasIntroduction = text.contains("## Introduction")
        return lines.count < 30 && !hasAbstract && !hasIntroduction
    }

    private func ocrPage(_ page: PDFPage) async throws -> String {
        guard let imageData = renderPageToPNG(page) else {
            throw OCRError.renderFailed
        }

        let base64 = imageData.base64EncodedString()
        return try await callAPI(base64Image: base64)
    }

    private func renderPageToPNG(_ page: PDFPage, dpi: CGFloat = 300) -> Data? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        page.draw(with: .mediaBox, to: context)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    private func callAPI(base64Image: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OCRError.noAPIKey }

        let url = URL(string: apiBaseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": 0.0,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": ocrPrompt],
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64Image)"]]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OCRError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OCRError.parseError
        }

        return content
    }
}

enum OCRError: LocalizedError {
    case noAPIKey
    case renderFailed
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenRouter API key configured"
        case .renderFailed: return "Failed to render PDF page to image"
        case .invalidResponse: return "Invalid response from API"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError: return "Failed to parse API response"
        }
    }
}
