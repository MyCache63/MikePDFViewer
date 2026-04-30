import Foundation

enum EMLParserError: Error {
    case invalidEncoding
    case malformedMessage
}

struct EMLParser {

    // MARK: - Public API

    static func parse(data: Data) throws -> EMLMessage {
        // EML files are 7-bit ASCII at the wire level. Body decoding handles charset.
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .ascii) else {
            throw EMLParserError.invalidEncoding
        }
        let part = parsePart(raw)
        return assembleMessage(from: part)
    }

    static func parse(url: URL) throws -> EMLMessage {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    // MARK: - Internal Part Tree

    private struct MimePart {
        var headers: [String: String]
        var rawHeaders: [(String, String)]
        var body: String              // raw body (may be base64/qp encoded)
        var subparts: [MimePart]
        var contentType: String { headers["content-type"] ?? "text/plain" }
        var contentTransferEncoding: String { headers["content-transfer-encoding"]?.lowercased() ?? "7bit" }
        var contentDisposition: String { headers["content-disposition"] ?? "" }
        var contentID: String? {
            guard let raw = headers["content-id"] else { return nil }
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        }

        var mediaType: String {
            let ct = contentType.lowercased()
            if let semi = ct.firstIndex(of: ";") {
                return String(ct[..<semi]).trimmingCharacters(in: .whitespaces)
            }
            return ct.trimmingCharacters(in: .whitespaces)
        }

        var charset: String {
            paramValue(in: contentType, key: "charset") ?? "utf-8"
        }

        var boundary: String? {
            paramValue(in: contentType, key: "boundary")
        }

        var filename: String? {
            paramValue(in: contentDisposition, key: "filename")
                ?? paramValue(in: contentType, key: "name")
        }

        var isAttachment: Bool {
            let dispLower = contentDisposition.lowercased()
            if dispLower.hasPrefix("attachment") { return true }
            if dispLower.hasPrefix("inline") && filename != nil && !mediaType.hasPrefix("text/") {
                return true
            }
            // Fallback: if there's a filename and we're not text/html/plain, treat as attachment
            if filename != nil && !mediaType.hasPrefix("text/") && !mediaType.hasPrefix("multipart/") {
                return true
            }
            return false
        }
    }

    // MARK: - Parsing

    private static func parsePart(_ raw: String) -> MimePart {
        let normalized = normalizeLineEndings(raw)
        let (headerSection, body) = splitHeadersAndBody(normalized)
        let (headerMap, rawHeaders) = parseHeaders(headerSection)

        var part = MimePart(
            headers: headerMap,
            rawHeaders: rawHeaders,
            body: body,
            subparts: []
        )

        // If multipart, split body on boundary
        if part.mediaType.hasPrefix("multipart/"), let boundary = part.boundary {
            part.subparts = splitMultipart(body: body, boundary: boundary).map { parsePart($0) }
        }

        return part
    }

    private static func splitHeadersAndBody(_ raw: String) -> (String, String) {
        // Headers end at first \n\n
        if let range = raw.range(of: "\n\n") {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        return (raw, "")
    }

    private static func parseHeaders(_ section: String) -> ([String: String], [(String, String)]) {
        // Unfold continuations: lines starting with whitespace are continuations of previous line
        var unfolded: [String] = []
        for line in section.components(separatedBy: "\n") {
            if line.isEmpty { continue }
            let first = line.first!
            if (first == " " || first == "\t") && !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                unfolded.append(line)
            }
        }

        var map: [String: String] = [:]
        var raw: [(String, String)] = []
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let decoded = decodeRFC2047(value)
            // For repeated headers (e.g. Received), keep the first; full list in raw
            if map[name] == nil {
                map[name] = decoded
            }
            raw.append((name, decoded))
        }
        return (map, raw)
    }

    private static func splitMultipart(body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        let close = "--" + boundary + "--"

        var parts: [String] = []
        var current = ""
        var inPart = false

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == close {
                if inPart { parts.append(current) }
                break
            } else if trimmed == delimiter {
                if inPart { parts.append(current) }
                current = ""
                inPart = true
            } else if inPart {
                current += line + "\n"
            }
        }
        // If close marker missing, take what we have
        if inPart && !current.isEmpty && parts.last != current {
            parts.append(current)
        }
        return parts
    }

    // MARK: - Assembly

    private static func assembleMessage(from root: MimePart) -> EMLMessage {
        var bodyHTML: String?
        var bodyPlain: String?
        var attachments: [EMLAttachment] = []
        var inlineImages: [EMLAttachment] = []

        walk(part: root,
             bodyHTML: &bodyHTML,
             bodyPlain: &bodyPlain,
             attachments: &attachments,
             inlineImages: &inlineImages)

        return EMLMessage(
            headers: root.headers,
            bodyHTML: bodyHTML,
            bodyPlain: bodyPlain,
            attachments: attachments,
            inlineImages: inlineImages
        )
    }

    private static func walk(part: MimePart,
                             bodyHTML: inout String?,
                             bodyPlain: inout String?,
                             attachments: inout [EMLAttachment],
                             inlineImages: inout [EMLAttachment]) {
        let media = part.mediaType

        if media.hasPrefix("multipart/") {
            for sub in part.subparts {
                walk(part: sub,
                     bodyHTML: &bodyHTML,
                     bodyPlain: &bodyPlain,
                     attachments: &attachments,
                     inlineImages: &inlineImages)
            }
            return
        }

        if part.isAttachment {
            if let attachment = makeAttachment(from: part) {
                if attachment.isInline && media.hasPrefix("image/") {
                    inlineImages.append(attachment)
                } else {
                    attachments.append(attachment)
                }
            }
            return
        }

        // Inline image without disposition (referenced by cid:)
        if media.hasPrefix("image/") && part.contentID != nil {
            if let attachment = makeAttachment(from: part, forceInline: true) {
                inlineImages.append(attachment)
            }
            return
        }

        // Body parts
        if media == "text/html", bodyHTML == nil {
            bodyHTML = decodeBody(part)
        } else if media == "text/plain", bodyPlain == nil {
            bodyPlain = decodeBody(part)
        }
    }

    private static func makeAttachment(from part: MimePart, forceInline: Bool = false) -> EMLAttachment? {
        let filename = part.filename ?? "attachment.\(extensionForMimeType(part.mediaType))"
        guard let data = decodeBodyData(part) else { return nil }
        let isInline = forceInline || part.contentDisposition.lowercased().hasPrefix("inline")
        return EMLAttachment(
            filename: filename,
            mimeType: part.mediaType,
            data: data,
            contentID: part.contentID,
            isInline: isInline
        )
    }

    // MARK: - Decoding

    private static func decodeBody(_ part: MimePart) -> String {
        guard let data = decodeBodyData(part) else { return part.body }
        let charset = part.charset
        let encoding = stringEncoding(for: charset)
        return String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) ?? part.body
    }

    private static func decodeBodyData(_ part: MimePart) -> Data? {
        let body = part.body
        switch part.contentTransferEncoding {
        case "base64":
            let cleaned = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters)
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body.data(using: .utf8)
        }
    }

    private static func decodeQuotedPrintable(_ input: String) -> Data {
        var output = Data()
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if c == "=" {
                let next = input.index(after: i)
                if next >= input.endIndex { i = input.endIndex; break }
                // Soft line break: =\r\n or =\n
                if input[next] == "\n" {
                    i = input.index(after: next)
                    continue
                }
                if input[next] == "\r" {
                    let nn = input.index(after: next)
                    if nn < input.endIndex && input[nn] == "\n" {
                        i = input.index(after: nn)
                    } else {
                        i = nn
                    }
                    continue
                }
                // Hex byte
                let nn = input.index(after: next)
                if nn < input.endIndex {
                    let hex = String(input[next...nn])
                    if let byte = UInt8(hex, radix: 16) {
                        output.append(byte)
                        i = input.index(after: nn)
                        continue
                    }
                }
                // Malformed — keep as-is
                output.append(UInt8(ascii: "="))
                i = next
            } else {
                if let scalar = c.asciiValue {
                    output.append(scalar)
                } else {
                    let bytes = String(c).utf8
                    for b in bytes { output.append(b) }
                }
                i = input.index(after: i)
            }
        }
        return output
    }

    private static func decodeRFC2047(_ input: String) -> String {
        // =?charset?encoding?encoded-text?=
        var result = input
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let nsInput = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsInput.length))
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }
            let charset = nsInput.substring(with: match.range(at: 1))
            let encoding = nsInput.substring(with: match.range(at: 2)).uppercased()
            let text = nsInput.substring(with: match.range(at: 3))
            let stringEncoding = self.stringEncoding(for: charset)

            var decoded: String?
            if encoding == "B" {
                if let data = Data(base64Encoded: text) {
                    decoded = String(data: data, encoding: stringEncoding)
                }
            } else if encoding == "Q" {
                // Q encoding: like quoted-printable but underscore = space
                let qText = text.replacingOccurrences(of: "_", with: " ")
                let data = decodeQuotedPrintable(qText)
                decoded = String(data: data, encoding: stringEncoding)
            }

            if let decoded {
                let nsResult = result as NSString
                result = nsResult.replacingCharacters(in: match.range, with: decoded)
            }
        }
        return result
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .ascii
        case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
        case "iso-8859-2": return .isoLatin2
        case "windows-1252", "cp1252": return .windowsCP1252
        case "windows-1251", "cp1251": return .windowsCP1251
        case "utf-16", "utf16": return .utf16
        default: return .utf8
        }
    }

    // MARK: - Helpers

    private static func normalizeLineEndings(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "\r\n", with: "\n")
                  .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func paramValue(in headerValue: String, key: String) -> String? {
        // Match key=value or key="value"
        let lowered = headerValue
        let parts = lowered.components(separatedBy: ";")
        for raw in parts.dropFirst() {
            let part = raw.trimmingCharacters(in: .whitespaces)
            let eq = part.range(of: "=")
            guard let eq else { continue }
            let k = String(part[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
            if k == key.lowercased() {
                var v = String(part[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
                    v = String(v.dropFirst().dropLast())
                }
                return v
            }
        }
        return nil
    }

    private static func extensionForMimeType(_ mime: String) -> String {
        switch mime.lowercased() {
        case "application/pdf": return "pdf"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "text/plain": return "txt"
        case "text/html": return "html"
        case "application/zip": return "zip"
        case "application/msword": return "doc"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.ms-excel": return "xls"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "text/calendar": return "ics"
        case "message/rfc822": return "eml"
        default: return "bin"
        }
    }
}
