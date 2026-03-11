import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ThumbnailSidebar: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    let totalPages: Int
    let documentVersion: Int
    @ObservedObject var bookmarkManager: BookmarkManager
    var onMovePage: ((Int, Int) -> Void)?

    @State private var draggedPage: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Bookmarks section
                    if !bookmarkManager.bookmarks.isEmpty {
                        bookmarkSection
                        Divider().padding(.horizontal, 8)
                    }

                    // Page thumbnails
                    ForEach(0..<totalPages, id: \.self) { index in
                        thumbnailRow(index: index)
                    }
                }
                .padding(8)
            }
            .onChange(of: currentPage) { _, newPage in
                withAnimation {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnailRow(index: Int) -> some View {
        ThumbnailItem(
            document: document,
            pageIndex: index,
            isSelected: index == currentPage,
            isBookmarked: bookmarkManager.isBookmarked(index),
            documentVersion: documentVersion
        )
        .id(index)
        .onTapGesture {
            currentPage = index
        }
        .onDrag {
            draggedPage = index
            return NSItemProvider(object: "\(index)" as NSString)
        }
        .onDrop(of: [.text], delegate: PageDropDelegate(
            targetIndex: index,
            draggedPage: $draggedPage,
            onMovePage: onMovePage
        ))
    }

    private var bookmarkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bookmarks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(bookmarkManager.bookmarks.sorted(by: { $0.pageIndex < $1.pageIndex })) { bookmark in
                Button {
                    currentPage = bookmark.pageIndex
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(bookmark.label)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(currentPage == bookmark.pageIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Drop Delegate

struct PageDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedPage: Int?
    let onMovePage: ((Int, Int) -> Void)?

    func performDrop(info: DropInfo) -> Bool {
        guard let from = draggedPage, from != targetIndex else {
            draggedPage = nil
            return false
        }
        onMovePage?(from, targetIndex)
        draggedPage = nil
        return true
    }

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedPage != nil
    }
}

// MARK: - Thumbnail Item

struct ThumbnailItem: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
    let isBookmarked: Bool
    let documentVersion: Int

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(8.5/11, contentMode: .fit)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(2)
                }
            }

            Text("\(pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 4)
        .onAppear {
            generateThumbnail()
        }
        .onChange(of: documentVersion) { _, _ in
            thumbnail = nil
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        DispatchQueue.global(qos: .utility).async {
            guard let page = document.page(at: pageIndex) else { return }
            let size = CGSize(width: 120, height: 160)
            let img = page.thumbnail(of: size, for: .mediaBox)
            DispatchQueue.main.async {
                thumbnail = img
            }
        }
    }
}
