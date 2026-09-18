import SwiftUI
import AppKit

/// Holds the open image and drives zoom from the toolbar. The scroll view does
/// the actual magnifying, so panning and pinch-zoom come for free.
@MainActor
final class ImageViewerController: ObservableObject {

    enum LoadError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name):
                return "\(name) isn't an image macOS can read."
            }
        }
    }

    @Published private(set) var image: NSImage?
    @Published private(set) var pixelSize: CGSize = .zero
    @Published private(set) var fileSizeText: String = ""

    /// Magnification the image opened at, which the slider treats as 100%.
    private var openScale: CGFloat = 1

    weak var scrollView: NSScrollView?
    weak var imageView: NSImageView?

    /// Reads and decodes off the caller's thread. The Grant Access flow keys
    /// off Cocoa 257 from Data(contentsOf:), so we still read bytes first.
    nonisolated static func loadPayload(at url: URL) throws -> Payload {
        let data = try Data(contentsOf: url)
        guard let loaded = NSImage(data: data) else {
            throw LoadError.unsupported(url.lastPathComponent)
        }
        let size: CGSize
        if let rep = loaded.representations.first, rep.pixelsWide > 0 {
            size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            size = loaded.size
        }
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        return Payload(image: loaded, pixelSize: size, fileSizeText: sizeText)
    }

    /// Applies a payload already read on a background queue.
    func apply(_ payload: Payload) {
        image = payload.image
        pixelSize = payload.pixelSize
        fileSizeText = payload.fileSizeText
    }

    /// Reads the bytes first so a sandbox denial surfaces as a real Cocoa
    /// error (the Grant Access flow keys off that) instead of a nil image.
    func load(url: URL) throws {
        apply(try Self.loadPayload(at: url))
    }

    func clear() {
        image = nil
        pixelSize = .zero
        fileSizeText = ""
    }

    /// NSImage is not Sendable; the box is only for hopping a finished decode
    /// onto the main actor after background I/O.
    struct Payload: @unchecked Sendable {
        let image: NSImage
        let pixelSize: CGSize
        let fileSizeText: String
    }

    var dimensionsText: String {
        guard pixelSize.width > 0 else { return "" }
        return "\(Int(pixelSize.width)) x \(Int(pixelSize.height)) px"
    }

    // MARK: Zoom

    func zoomIn() { setMagnification(magnification * 1.25, centerOnImage: false) }
    func zoomOut() { setMagnification(magnification / 1.25, centerOnImage: false) }
    func actualSize() { setMagnification(1, centerOnImage: true) }

    /// Fills the window, enlarging a small image if that is what it takes.
    func fitToWindow() { setMagnification(fitScale(allowEnlarging: true), centerOnImage: true) }

    /// Used on first display: shrinks a big screenshot to fit, but leaves a
    /// small image at its own size instead of blowing it up.
    func fitOnOpen() {
        openScale = min(fitScale(allowEnlarging: false), 1)
        setMagnification(openScale, centerOnImage: true)
    }

    /// 1.0 restores the size the image opened at.
    func setRelativeZoom(_ value: Double) {
        setMagnification(openScale * CGFloat(value), centerOnImage: false)
    }

    private var magnification: CGFloat { scrollView?.magnification ?? 1 }

    private func fitScale(allowEnlarging: Bool) -> CGFloat {
        guard let scrollView, let imageView,
              imageView.bounds.width > 0, imageView.bounds.height > 0 else { return 1 }
        let clip = scrollView.contentView.bounds.size
        let scale = min(clip.width / imageView.bounds.width,
                        clip.height / imageView.bounds.height)
        return allowEnlarging ? scale : min(scale, 1)
    }

    private func setMagnification(_ value: CGFloat, centerOnImage: Bool) {
        guard let scrollView else { return }
        let clamped = max(0.05, min(value, 40))
        let center: NSPoint
        if centerOnImage, let imageView {
            center = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        } else {
            let visible = scrollView.documentVisibleRect
            center = NSPoint(x: visible.midX, y: visible.midY)
        }
        scrollView.setMagnification(clamped, centeredAt: center)
    }
}

/// Keeps a document view smaller than the window centred instead of pinned to
/// the bottom-left corner, which is what a plain NSClipView does.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let container = documentView else { return rect }
        if rect.width > container.frame.width {
            rect.origin.x = (container.frame.width - rect.width) / 2
        }
        if rect.height > container.frame.height {
            rect.origin.y = (container.frame.height - rect.height) / 2
        }
        return rect
    }
}

struct ImageViewerView: NSViewRepresentable {
    @ObservedObject var controller: ImageViewerController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 40
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor

        let imageView = NSImageView()
        // Magnification does the scaling, so the view itself must not resample.
        imageView.imageScaling = .scaleNone
        imageView.animates = true          // animated GIFs play
        imageView.imageAlignment = .alignCenter
        scrollView.documentView = imageView

        controller.scrollView = scrollView
        controller.imageView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }
        guard imageView.image !== controller.image else { return }
        imageView.image = controller.image
        let size = controller.pixelSize.width > 0
            ? controller.pixelSize
            : (controller.image?.size ?? .zero)
        imageView.frame = NSRect(origin: .zero, size: size)
        // The clip view has no size until the next layout pass.
        DispatchQueue.main.async { controller.fitOnOpen() }
    }
}
