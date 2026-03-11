import SwiftUI
import PDFKit

struct ThumbnailSidebar: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    let totalPages: Int
    let documentVersion: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        ThumbnailItem(
                            document: document,
                            pageIndex: index,
                            isSelected: index == currentPage,
                            documentVersion: documentVersion
                        )
                        .id(index)
                        .onTapGesture {
                            currentPage = index
                        }
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
}

struct ThumbnailItem: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
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
