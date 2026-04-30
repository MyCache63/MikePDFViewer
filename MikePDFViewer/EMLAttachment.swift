import Foundation
import UniformTypeIdentifiers

struct EMLAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let contentID: String?
    let isInline: Bool

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var fileExtension: String {
        if let ext = (filename as NSString).pathExtension as String?, !ext.isEmpty {
            return ext.lowercased()
        }
        if let utType = UTType(mimeType: mimeType), let ext = utType.preferredFilenameExtension {
            return ext
        }
        return "bin"
    }

    var systemIconName: String {
        switch fileExtension {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "play.rectangle"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic": return "photo"
        case "zip", "tar", "gz": return "doc.zipper"
        case "txt": return "doc.plaintext"
        case "eml": return "envelope"
        case "ics": return "calendar"
        case "mp3", "wav", "m4a", "aac": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "film"
        default: return "doc"
        }
    }
}
