import Foundation
import AppKit

/// Lightweight wrapper around a parsed markdown file. Holds the raw source text and
/// produces a styled NSAttributedString suitable for display in NSTextView.
struct MarkdownDocument {
    let source: String
    let url: URL?

    init(source: String, url: URL? = nil) {
        self.source = source
        self.url = url
    }

    init(url: URL) throws {
        self.url = url
        self.source = try String(contentsOf: url, encoding: .utf8)
    }

    /// Render the markdown to a styled NSAttributedString. Applies visible styling
    /// for headers, code blocks, blockquotes, inline code, bold and italic.
    func styledAttributedString() -> NSAttributedString {
        let parseOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        let attr: AttributedString
        do {
            attr = try AttributedString(markdown: source, options: parseOptions)
        } catch {
            return fallbackPlainText()
        }

        // Convert to NSMutableAttributedString so we can apply AppKit fonts.
        let mutable = NSMutableAttributedString(attr)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        mutable.addAttribute(.font, value: bodyFont,
                             range: NSRange(location: 0, length: mutable.length))

        // Walk presentationIntent and inlinePresentationIntent runs to apply styling.
        // These attribute keys come from the Foundation AttributedString markdown scope.
        let intentKey = NSAttributedString.Key("NSPresentationIntent")
        let inlineKey = NSAttributedString.Key("NSInlinePresentationIntent")

        mutable.enumerateAttribute(intentKey, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let intent = value as? PresentationIntent else { return }
            applyBlockStyle(mutable: mutable, range: range, intent: intent)
        }

        mutable.enumerateAttribute(inlineKey, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            // The inline intent is stored as Int (raw value of InlinePresentationIntent option set).
            guard let raw = value as? UInt else { return }
            let inline = InlinePresentationIntent(rawValue: raw)
            applyInlineStyle(mutable: mutable, range: range, inline: inline)
        }

        // Paragraph styling: line spacing for readability.
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 8
        mutable.addAttribute(.paragraphStyle, value: para,
                             range: NSRange(location: 0, length: mutable.length))

        return mutable
    }

    private func fallbackPlainText() -> NSAttributedString {
        let fallback = NSMutableAttributedString(string: source)
        fallback.addAttribute(.font,
                              value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                              range: NSRange(location: 0, length: fallback.length))
        return fallback
    }

    private func applyBlockStyle(mutable: NSMutableAttributedString,
                                 range: NSRange,
                                 intent: PresentationIntent) {
        for component in intent.components {
            switch component.kind {
            case .header(level: let level):
                let sizes: [CGFloat] = [24, 20, 17, 15, 14, 13]
                let size = sizes[min(max(level - 1, 0), sizes.count - 1)]
                mutable.addAttribute(.font,
                                     value: NSFont.systemFont(ofSize: size, weight: .bold),
                                     range: range)
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)

            case .codeBlock:
                mutable.addAttribute(.font,
                                     value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                     range: range)
                mutable.addAttribute(.backgroundColor,
                                     value: NSColor(calibratedWhite: 0.94, alpha: 1.0),
                                     range: range)

            case .blockQuote:
                mutable.addAttribute(.foregroundColor,
                                     value: NSColor.secondaryLabelColor,
                                     range: range)

            default:
                break
            }
        }
    }

    private func applyInlineStyle(mutable: NSMutableAttributedString,
                                  range: NSRange,
                                  inline: InlinePresentationIntent) {
        if inline.contains(.code) {
            mutable.addAttribute(.font,
                                 value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                 range: range)
            mutable.addAttribute(.backgroundColor,
                                 value: NSColor(calibratedWhite: 0.94, alpha: 1.0),
                                 range: range)
        }
        if inline.contains(.stronglyEmphasized) {
            applyTrait(mask: .boldFontMask, mutable: mutable, range: range)
        }
        if inline.contains(.emphasized) {
            applyTrait(mask: .italicFontMask, mutable: mutable, range: range)
        }
    }

    private func applyTrait(mask: NSFontTraitMask,
                            mutable: NSMutableAttributedString,
                            range: NSRange) {
        mutable.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let bolded = NSFontManager.shared.convert(current, toHaveTrait: mask)
            mutable.addAttribute(.font, value: bolded, range: subRange)
        }
    }
}
