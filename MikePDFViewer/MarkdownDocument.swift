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

    /// Render the markdown to a styled NSAttributedString.
    ///
    /// AttributedString(markdown:) gives us block structure via `presentationIntent`
    /// but does not insert character-level newlines between blocks. We walk the runs
    /// and rebuild a fresh NSMutableAttributedString, inserting paragraph breaks at
    /// block boundaries and applying header/code/quote styling per block.
    func styledAttributedString() -> NSAttributedString {
        let parseOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        let parsed: AttributedString
        do {
            parsed = try AttributedString(markdown: source, options: parseOptions)
        } catch {
            return fallbackPlainText()
        }

        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 13)
        var prevBlockID: Int? = nil
        var prevWasListItem = false

        for run in parsed.runs {
            let intent = run.presentationIntent
            let currentID = intent?.blockIdentity
            let isListItem = intent?.isListItem ?? false

            // Insert a separator if we crossed a block boundary.
            if let prev = prevBlockID, prev != currentID {
                let separator = (prevWasListItem && isListItem) ? "\n" : "\n\n"
                result.append(NSAttributedString(string: separator))
            }

            let runText = String(parsed[run.range].characters)
            let segment = NSMutableAttributedString(string: runText)
            let segRange = NSRange(location: 0, length: segment.length)
            segment.addAttribute(.font, value: bodyFont, range: segRange)

            if let intent = intent {
                applyBlockStyle(mutable: segment, range: segRange, intent: intent)
            }
            if let inline = run.inlinePresentationIntent {
                applyInlineStyle(mutable: segment, range: segRange, inline: inline)
            }

            // Apply link styling for clickable URLs.
            if let link = run.link {
                segment.addAttribute(.link, value: link, range: segRange)
                segment.addAttribute(.foregroundColor, value: NSColor.linkColor, range: segRange)
                segment.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: segRange)
            }

            result.append(segment)
            prevBlockID = currentID
            prevWasListItem = isListItem
        }

        // Paragraph styling for line spacing.
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 6
        result.addAttribute(.paragraphStyle, value: para,
                            range: NSRange(location: 0, length: result.length))

        return result
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

            case .listItem:
                // Prepend a bullet marker. Detect if part of an ordered list via outer components.
                let isOrdered = intent.components.contains(where: {
                    if case .orderedList = $0.kind { return true } else { return false }
                })
                let marker: String
                if isOrdered {
                    if case let .listItem(ordinal) = component.kind {
                        marker = "\(ordinal). "
                    } else {
                        marker = "• "
                    }
                } else {
                    marker = "• "
                }
                let bullet = NSAttributedString(string: marker, attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                mutable.insert(bullet, at: range.location)

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
            let newFont = NSFontManager.shared.convert(current, toHaveTrait: mask)
            mutable.addAttribute(.font, value: newFont, range: subRange)
        }
    }
}

private extension PresentationIntent {
    var isListItem: Bool {
        components.contains { component in
            if case .listItem = component.kind { return true }
            return false
        }
    }

    /// Identity of the deepest (leaf) block — uniquely identifies a single
    /// paragraph / header / list item etc.
    var blockIdentity: Int? {
        components.first?.identity
    }
}
