import Foundation

/// Reader typography settings. Independent of theme — a host can swap themes
/// without disturbing the user's font/size preferences and vice-versa.
///
/// All 5 settings map to CSS variables on `:root` of the rendered HTML, so
/// changing any one re-flows the document without re-parsing.
public struct MarkdownTypography: Equatable, Sendable {

    public enum FontFamily: String, CaseIterable, Sendable {
        case system   // -apple-system / SF Pro
        case serif    // Iowan Old Style / Georgia
        case mono     // SF Mono / Menlo
        case quattro  // iA-Writer-style fallback (system-ui until iA fonts are bundled)

        public var displayName: String {
            switch self {
            case .system:  return "System"
            case .serif:   return "Serif"
            case .mono:    return "Monospace"
            case .quattro: return "Quattro"
            }
        }

        public var cssValue: String {
            switch self {
            case .system:
                return "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Helvetica, Arial, sans-serif"
            case .serif:
                return "'Iowan Old Style', Palatino, Georgia, 'Times New Roman', serif"
            case .mono:
                return "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace"
            case .quattro:
                // Approximation until iA fonts are bundled — sans with slightly wider tracking.
                return "'Inter', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
            }
        }
    }

    public enum ContentWidth: String, CaseIterable, Sendable {
        case narrow    // ~60ch — focused reading
        case standard  // ~72ch — default
        case wide      // ~90ch — wide-screen
        case full      // fill viewport

        public var displayName: String {
            switch self {
            case .narrow:   return "Narrow"
            case .standard: return "Standard"
            case .wide:     return "Wide"
            case .full:     return "Full Width"
            }
        }

        public var cssValue: String {
            switch self {
            case .narrow:   return "640px"
            case .standard: return "820px"
            case .wide:     return "1040px"
            case .full:     return "100%"
            }
        }
    }

    public enum ParagraphSpacing: String, CaseIterable, Sendable {
        case tight, normal, loose

        public var displayName: String {
            switch self {
            case .tight:  return "Tight"
            case .normal: return "Normal"
            case .loose:  return "Loose"
            }
        }

        public var cssValue: String {
            switch self {
            case .tight:  return "8px"
            case .normal: return "16px"
            case .loose:  return "28px"
            }
        }
    }

    public var fontFamily: FontFamily
    public var fontSize: Int                 // pt — clamped to 11...22
    public var lineHeight: Double            // 1.30 ... 2.00
    public var contentWidth: ContentWidth
    public var paragraphSpacing: ParagraphSpacing

    public init(fontFamily: FontFamily = .system,
                fontSize: Int = 16,
                lineHeight: Double = 1.6,
                contentWidth: ContentWidth = .standard,
                paragraphSpacing: ParagraphSpacing = .normal) {
        self.fontFamily = fontFamily
        self.fontSize = max(11, min(fontSize, 22))
        self.lineHeight = max(1.3, min(lineHeight, 2.0))
        self.contentWidth = contentWidth
        self.paragraphSpacing = paragraphSpacing
    }

    public static let `default` = MarkdownTypography()

    /// Emit the CSS variable overrides as inline `:root { ... }` rules. Inserted
    /// after the theme bundle so user typography always wins.
    public var cssOverrides: String {
        return """
        :root {
            --md-font-family: \(fontFamily.cssValue);
            --md-font-size: \(fontSize)px;
            --md-line-height: \(String(format: "%.2f", lineHeight));
            --md-content-width: \(contentWidth.cssValue);
            --md-para-spacing: \(paragraphSpacing.cssValue);
        }
        .markdown-body p, .markdown-body ul, .markdown-body ol,
        .markdown-body blockquote, .markdown-body pre, .markdown-body table {
            margin-bottom: var(--md-para-spacing) !important;
        }
        """
    }
}
