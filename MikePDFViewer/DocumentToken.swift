import Foundation
import PDFKit
import ObjectiveC

/// A number that identifies one PDFDocument instance and is never reused.
///
/// The app used `ObjectIdentifier(document)` for this, which is only the
/// object's memory address. Once a document is released (its window closes,
/// or goes to sleep) the next document very often gets the same address:
/// measured 49 times in 50. Thumbnails cached under that address then showed
/// the old file's pages next to the new file (Michael, 4 Oct 2026: dessert
/// labels open, wedding script in the sidebar). This token is stored on the
/// document itself, so it lives and dies with it and is never handed out twice.
enum DocumentToken {
    private static let associationKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private static let lock = NSLock()
    private static var nextToken = 0

    /// Safe to call from any thread; thumbnails render on background queues.
    static func token(for document: PDFDocument) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = objc_getAssociatedObject(document, associationKey) as? Int {
            return existing
        }
        nextToken += 1
        objc_setAssociatedObject(document, associationKey, nextToken, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return nextToken
    }
}
