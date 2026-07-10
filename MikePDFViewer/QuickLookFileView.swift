import SwiftUI
import Quartz

/// Embeds macOS Quick Look (the same engine as Finder's Space-bar preview)
/// inside the app. Renders PowerPoint, Word, Keynote, Pages, and dozens of
/// other formats instantly with native fidelity, no conversion step.
struct QuickLookFileView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let current = view.previewItem as? NSURL
        if current == nil || (current! as URL) != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}
