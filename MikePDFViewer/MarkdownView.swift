import SwiftUI
import AppKit

/// SwiftUI wrapper around an NSTextView that displays a styled markdown document.
/// Provides scrolling, selection, clickable external links, and in-document anchor
/// scrolling for `[link](#slug)` jumps.
struct MarkdownView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let anchors: [String: NSRange]

    func makeCoordinator() -> Coordinator {
        Coordinator(anchors: anchors)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.textStorage?.setAttributedString(attributedString)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.anchors = anchors
        context.coordinator.textView = textView
        textView.textStorage?.setAttributedString(attributedString)
    }

    /// Handles link clicks: in-document `#slug` anchors scroll within the view;
    /// http(s) URLs open in the default browser; everything else is suppressed
    /// so we don't get LaunchServices error -50.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var anchors: [String: NSRange]
        weak var textView: NSTextView?

        init(anchors: [String: NSRange]) {
            self.anchors = anchors
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let urlString: String
            if let url = link as? URL {
                urlString = url.absoluteString
            } else if let s = link as? String {
                urlString = s
            } else {
                return true  // unknown — swallow rather than let NSTextView open it
            }

            // Anchor jump: "#some-slug" or full URL whose fragment is the only meaningful part.
            if urlString.hasPrefix("#") {
                jumpToAnchor(slug: String(urlString.dropFirst()), in: textView)
                return true
            }
            if let url = URL(string: urlString),
               url.scheme == nil || url.scheme == "applewebdata" || url.scheme == "file" && url.host == nil,
               let fragment = url.fragment, !fragment.isEmpty {
                jumpToAnchor(slug: fragment, in: textView)
                return true
            }

            // External http(s) — open in browser.
            if let url = URL(string: urlString),
               let scheme = url.scheme,
               scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                return true
            }

            // Mailto.
            if let url = URL(string: urlString), url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                return true
            }

            // Anything else: swallow, don't let NSTextView throw -50.
            return true
        }

        private func jumpToAnchor(slug: String, in textView: NSTextView) {
            // Try exact match first, then a normalized fallback.
            let candidate = anchors[slug] ?? anchors[MarkdownDocument.slugify(slug)]
            guard let range = candidate else { return }
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }
}
