import Foundation
import AppKit

/// Lightweight wrapper around a parsed markdown file. Holds the raw source text and
/// produces a styled NSAttributedString suitable for display in NSTextView, plus a
/// dictionary mapping anchor slugs (e.g. "table-of-contents") to character ranges so
/// in-document `[link](#slug)` clicks can scroll instead of failing.
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

    enum BlockKind: Equatable {
        case paragraph
        case header(Int)
        case codeBlock
        case blockQuote
        case listItem(ordered: Bool, ordinal: Int)
        case thematicBreak
    }

    /// Render the markdown to a styled NSAttributedString and return a slug→range
    /// dictionary for header anchors.
    func styledAttributedStringWithAnchors() -> (text: NSAttributedString, anchors: [String: NSRange]) {
        let parseOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        let parsed: AttributedString
        do {
            parsed = try AttributedString(markdown: source, options: parseOptions)
        } catch {
            return (fallbackPlainText(), [:])
        }

        // Group runs by their leaf block identity.
        struct Block {
            var kind: BlockKind
            var identity: Int?
            var runs: [AttributedString.Runs.Run] = []
            var plainText: String = ""
        }

        var blocks: [Block] = []
        var current: Block?

        for run in parsed.runs {
            let id = run.presentationIntent?.components.first?.identity
            if id != current?.identity {
                if let c = current { blocks.append(c) }
                current = Block(kind: classify(run.presentationIntent), identity: id)
            }
            current!.runs.append(run)
            current!.plainText += String(parsed[run.range].characters)
        }
        if let c = current { blocks.append(c) }

        // Emit, tracking header ranges for anchors.
        let result = NSMutableAttributedString()
        var anchors: [String: NSRange] = [:]
        let bodyFont = NSFont.systemFont(ofSize: 13)
        var prevKind: BlockKind = .paragraph

        for (i, block) in blocks.enumerated() {
            if i > 0 {
                let separator = (isListItem(prevKind) && isListItem(block.kind)) ? "\n" : "\n\n"
                result.append(NSAttributedString(string: separator))
            }
            let blockStart = result.length

            // Bullet for list items
            if case .listItem(let ordered, let ordinal) = block.kind {
                let marker = ordered ? "\(ordinal). " : "• "
                let bullet = NSAttributedString(string: marker, attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                result.append(bullet)
            }

            // Emit each run with its inline + block styling.
            for run in block.runs {
                let text = String(parsed[run.range].characters)
                let segment = NSMutableAttributedString(string: text)
                let segRange = NSRange(location: 0, length: segment.length)
                segment.addAttribute(.font, value: bodyFont, range: segRange)

                applyBlockStyle(mutable: segment, range: segRange, kind: block.kind)
                if let inline = run.inlinePresentationIntent {
                    applyInlineStyle(mutable: segment, range: segRange, inline: inline)
                }
                if let link = run.link {
                    segment.addAttribute(.link, value: link, range: segRange)
                    segment.addAttribute(.foregroundColor, value: NSColor.linkColor, range: segRange)
                    segment.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: segRange)
                }
                result.append(segment)
            }

            if case .header = block.kind {
                let range = NSRange(location: blockStart, length: result.length - blockStart)
                let slug = Self.slugify(block.plainText)
                anchors[slug] = range
            }
            prevKind = block.kind
        }

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 6
        result.addAttribute(.paragraphStyle, value: para,
                            range: NSRange(location: 0, length: result.length))

        return (result, anchors)
    }

    /// GitHub-style slug: lowercase, strip punctuation, spaces → hyphens, collapse
    /// adjacent hyphens. Matches the convention markdown TOC tools use when emitting
    /// `[Heading Name](#heading-name)` links.
    static func slugify(_ text: String) -> String {
        var slug = text.lowercased()
        slug = String(slug.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == " "
                || scalar == "-"
                || scalar == "_"
        })
        slug = slug.replacingOccurrences(of: " ", with: "-")
        slug = slug.replacingOccurrences(of: "_", with: "-")
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Helpers

    private func fallbackPlainText() -> NSAttributedString {
        let fallback = NSMutableAttributedString(string: source)
        fallback.addAttribute(.font,
                              value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                              range: NSRange(location: 0, length: fallback.length))
        return fallback
    }

    private func classify(_ intent: PresentationIntent?) -> BlockKind {
        guard let intent = intent else { return .paragraph }

        var isOrdered = false
        var isUnordered = false
        var listItemOrdinal: Int? = nil

        for component in intent.components {
            switch component.kind {
            case .header(level: let lvl):
                return .header(lvl)
            case .codeBlock:
                return .codeBlock
            case .blockQuote:
                return .blockQuote
            case .thematicBreak:
                return .thematicBreak
            case .orderedList:
                isOrdered = true
            case .unorderedList:
                isUnordered = true
            case .listItem(ordinal: let n):
                listItemOrdinal = n
            default:
                break
            }
        }
        if let n = listItemOrdinal {
            return .listItem(ordered: isOrdered && !isUnordered, ordinal: n)
        }
        return .paragraph
    }

    private func isListItem(_ kind: BlockKind) -> Bool {
        if case .listItem = kind { return true }
        return false
    }

    private func applyBlockStyle(mutable: NSMutableAttributedString,
                                 range: NSRange,
                                 kind: BlockKind) {
        switch kind {
        case .header(let level):
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
