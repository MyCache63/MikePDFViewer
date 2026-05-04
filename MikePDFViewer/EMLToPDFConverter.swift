import Foundation
import PDFKit
import AppKit

@MainActor
final class EMLToPDFConverter: NSObject {

    enum ConversionError: Error {
        case htmlBuildFailed
        case pdfRenderFailed
        case parsedDocumentInvalid
    }

    /// Convert a parsed EML message into a PDFDocument.
    /// `loadExternalImages`: if false, remote <img src=http...> tags are stripped before rendering.
    static func convert(_ message: EMLMessage, loadExternalImages: Bool = false) async throws -> PDFDocument {
        let html = buildHTML(from: message, loadExternalImages: loadExternalImages)
        let pdfData = try await renderHTMLToPDF(html: html, loadExternalImages: loadExternalImages)
        guard let document = PDFDocument(data: pdfData) else {
            throw ConversionError.parsedDocumentInvalid
        }
        return document
    }

    // MARK: - HTML Construction

    static func buildHTML(from message: EMLMessage, loadExternalImages: Bool) -> String {
        let header = buildHeaderSection(message)
        var body = buildBodySection(message)
        body = inlineCidImages(in: body, with: message.inlineImages)
        if !loadExternalImages {
            body = blockExternalImages(in: body)
        }
        let attachmentsList = buildAttachmentsSection(message)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @page { margin: 0.5in; }
                body {
                    font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
                    font-size: 12pt;
                    color: #1a1a1a;
                    margin: 0;
                    padding: 0;
                }
                .email-headers {
                    border-bottom: 2px solid #ccc;
                    padding-bottom: 12px;
                    margin-bottom: 16px;
                }
                .email-headers .subject {
                    font-size: 18pt;
                    font-weight: 600;
                    margin-bottom: 8px;
                    color: #000;
                }
                .email-headers .header-row {
                    margin: 2px 0;
                    font-size: 11pt;
                }
                .email-headers .header-label {
                    display: inline-block;
                    width: 60px;
                    color: #666;
                    font-weight: 500;
                }
                .email-headers .header-value {
                    color: #1a1a1a;
                }
                .email-body {
                    margin-top: 12px;
                    line-height: 1.5;
                }
                .email-body img {
                    max-width: 100%;
                    height: auto;
                }
                .plain-text-body {
                    font-family: "SF Mono", Menlo, Consolas, monospace;
                    font-size: 11pt;
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                .attachments-section {
                    margin-top: 24px;
                    padding-top: 16px;
                    border-top: 1px solid #ddd;
                }
                .attachments-title {
                    font-size: 12pt;
                    font-weight: 600;
                    margin-bottom: 8px;
                    color: #444;
                }
                .attachment-item {
                    padding: 6px 10px;
                    margin: 4px 0;
                    background: #f4f4f4;
                    border-left: 3px solid #888;
                    border-radius: 2px;
                    font-size: 10pt;
                }
                .attachment-name { font-weight: 500; }
                .attachment-meta { color: #666; font-size: 9pt; }
                .blocked-image-notice {
                    display: inline-block;
                    padding: 4px 8px;
                    background: #fff8e1;
                    border: 1px dashed #f0c060;
                    border-radius: 3px;
                    font-size: 9pt;
                    color: #8a6d00;
                    margin: 2px;
                }
            </style>
        </head>
        <body>
            \(header)
            <div class="email-body">
                \(body)
            </div>
            \(attachmentsList)
        </body>
        </html>
        """
    }

    private static func buildHeaderSection(_ message: EMLMessage) -> String {
        var rows = ""
        let from = htmlEscape(message.from)
        let to = htmlEscape(message.to)
        let cc = htmlEscape(message.cc)
        let date = htmlEscape(message.date)
        let subject = htmlEscape(message.subject)

        if !from.isEmpty {
            rows += "<div class=\"header-row\"><span class=\"header-label\">From:</span><span class=\"header-value\">\(from)</span></div>"
        }
        if !to.isEmpty {
            rows += "<div class=\"header-row\"><span class=\"header-label\">To:</span><span class=\"header-value\">\(to)</span></div>"
        }
        if !cc.isEmpty {
            rows += "<div class=\"header-row\"><span class=\"header-label\">Cc:</span><span class=\"header-value\">\(cc)</span></div>"
        }
        if !date.isEmpty {
            rows += "<div class=\"header-row\"><span class=\"header-label\">Date:</span><span class=\"header-value\">\(date)</span></div>"
        }

        return """
        <div class="email-headers">
            <div class="subject">\(subject)</div>
            \(rows)
        </div>
        """
    }

    private static func buildBodySection(_ message: EMLMessage) -> String {
        if let html = message.bodyHTML, !html.isEmpty {
            return sanitizeHTMLBody(html)
        }
        if let plain = message.bodyPlain, !plain.isEmpty {
            return "<div class=\"plain-text-body\">\(htmlEscape(plain))</div>"
        }
        return "<div class=\"plain-text-body\"><em>(empty message body)</em></div>"
    }

    private static func buildAttachmentsSection(_ message: EMLMessage) -> String {
        guard message.hasAttachments else { return "" }
        var items = ""
        for att in message.attachments {
            items += """
            <div class="attachment-item">
                <span class="attachment-name">\(htmlEscape(att.filename))</span>
                <span class="attachment-meta"> — \(htmlEscape(att.mimeType)), \(att.sizeFormatted)</span>
            </div>
            """
        }
        return """
        <div class="attachments-section">
            <div class="attachments-title">Attachments (\(message.attachments.count))</div>
            \(items)
        </div>
        """
    }

    // MARK: - HTML Sanitization

    private static func sanitizeHTMLBody(_ html: String) -> String {
        // Strip <html>, <head>, <body> wrappers — we provide our own
        var stripped = html

        // Remove <head>...</head>
        if let headRange = stripped.range(of: "<head", options: .caseInsensitive),
           let headEnd = stripped.range(of: "</head>", options: .caseInsensitive, range: headRange.lowerBound..<stripped.endIndex) {
            stripped.removeSubrange(headRange.lowerBound..<headEnd.upperBound)
        }

        // If there's a <body> tag, take only what's inside
        if let bodyOpenRange = stripped.range(of: "<body", options: .caseInsensitive),
           let bodyOpenEnd = stripped.range(of: ">", range: bodyOpenRange.upperBound..<stripped.endIndex),
           let bodyCloseRange = stripped.range(of: "</body>", options: .caseInsensitive) {
            stripped = String(stripped[bodyOpenEnd.upperBound..<bodyCloseRange.lowerBound])
        }

        // Strip remaining <html> tags
        stripped = stripped.replacingOccurrences(of: "<html[^>]*>", with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "</html>", with: "", options: .regularExpression)

        // Remove <script>...</script> for safety
        stripped = stripped.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)

        return stripped
    }

    private static func inlineCidImages(in html: String, with images: [EMLAttachment]) -> String {
        var result = html
        for image in images {
            guard let cid = image.contentID else { continue }
            let dataURL = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            // Match src="cid:CID" or src='cid:CID' (case-insensitive)
            for variant in ["cid:\(cid)", "CID:\(cid)"] {
                result = result.replacingOccurrences(of: "\"\(variant)\"", with: "\"\(dataURL)\"")
                result = result.replacingOccurrences(of: "'\(variant)'", with: "'\(dataURL)'")
            }
        }
        return result
    }

    private static func blockExternalImages(in html: String) -> String {
        // Replace <img src="http..."> with a placeholder notice
        let pattern = "<img[^>]*src=[\"'](https?://[^\"']+)[\"'][^>]*>"
        let replacement = "<span class=\"blocked-image-notice\">[remote image blocked]</span>"
        return html.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - PDF Rendering via WKWebView

    private static func renderHTMLToPDF(html: String, loadExternalImages: Bool) async throws -> Data {
        return try await HTMLToPDFRenderer.render(html: html, loadExternalImages: loadExternalImages)
    }
}
