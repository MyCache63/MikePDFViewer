import Foundation

struct EMLMessage {
    var headers: [String: String]
    var bodyHTML: String?
    var bodyPlain: String?
    var attachments: [EMLAttachment]
    var inlineImages: [EMLAttachment]

    var from: String { headers["from"] ?? "" }
    var to: String { headers["to"] ?? "" }
    var cc: String { headers["cc"] ?? "" }
    var bcc: String { headers["bcc"] ?? "" }
    var subject: String { headers["subject"] ?? "(no subject)" }
    var date: String { headers["date"] ?? "" }
    var replyTo: String { headers["reply-to"] ?? "" }

    var hasAttachments: Bool { !attachments.isEmpty }
}
