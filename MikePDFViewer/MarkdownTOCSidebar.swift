import SwiftUI

/// Table-of-contents sidebar for the markdown reader. Shows headings as a
/// flat indented list (level 1-6 → indentation levels). Clicking a heading
/// jumps to its anchor in the WKWebView via a closure handed in by the host.
struct MarkdownTOCSidebar: View {
    let entries: [MarkdownToHTML.TOCEntry]
    let stats: ReadingStats
    let onJump: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statsHeader
            Divider()
            if entries.isEmpty {
                Text("No headings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            tocRow(entry)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reading Stats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft").font(.caption2)
                Text("\(stats.wordCount) words").font(.caption).monospacedDigit()
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.caption2)
                Text(stats.readingTimeText).font(.caption).monospacedDigit()
            }
            HStack(spacing: 6) {
                Image(systemName: "list.bullet").font(.caption2)
                Text("\(entries.count) headings").font(.caption).monospacedDigit()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tocRow(_ entry: MarkdownToHTML.TOCEntry) -> some View {
        Button {
            onJump(entry.slug)
        } label: {
            HStack(alignment: .top, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: rowFontSize(for: entry.level)))
                    .fontWeight(entry.level <= 2 ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(max(0, entry.level - 1)) * 10)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12
        case 3: return 12
        default: return 11
        }
    }
}

/// Lightweight word/reading-time computation. Reading speed assumes ~220 WPM.
struct ReadingStats: Equatable {
    let wordCount: Int
    let estimatedMinutes: Int

    var readingTimeText: String {
        if estimatedMinutes < 1 { return "< 1 min read" }
        if estimatedMinutes == 1 { return "1 min read" }
        return "\(estimatedMinutes) min read"
    }

    init(source: String) {
        let words = source.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        self.wordCount = words.count
        self.estimatedMinutes = max(0, Int((Double(self.wordCount) / 220.0).rounded()))
    }

    static let empty = ReadingStats(source: "")
}
