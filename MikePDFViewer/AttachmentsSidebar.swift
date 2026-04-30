import SwiftUI
import UniformTypeIdentifiers

struct AttachmentsSidebar: View {
    let attachments: [EMLAttachment]
    @Binding var loadExternalImages: Bool
    let onReloadWithImages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text("Email")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            // Image loading toggle
            HStack {
                Toggle(isOn: $loadExternalImages) {
                    Text("Load remote images")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: loadExternalImages) { _, _ in
                    onReloadWithImages()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if attachments.isEmpty {
                VStack {
                    Spacer()
                    Text("No attachments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Text("Attachments (\(attachments.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 240)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct AttachmentRow: View {
    let attachment: EMLAttachment
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: attachment.systemIconName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(attachment.sizeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Button {
                    saveAttachment()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    openAttachment()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private func saveAttachment() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename
        if let utType = UTType(mimeType: attachment.mimeType) {
            panel.allowedContentTypes = [utType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            try? attachment.data.write(to: url)
        }
    }

    private func openAttachment() {
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = attachment.filename.replacingOccurrences(of: "/", with: "_")
        let fileURL = tempDir.appendingPathComponent(safeName)
        do {
            try attachment.data.write(to: fileURL)
            // PDF? Open in MikePDFViewer (this app)
            if attachment.fileExtension == "pdf" {
                NotificationCenter.default.post(
                    name: .pdfOpenFile,
                    object: nil,
                    userInfo: ["url": fileURL]
                )
            } else if attachment.fileExtension == "eml" {
                NotificationCenter.default.post(
                    name: .pdfOpenFile,
                    object: nil,
                    userInfo: ["url": fileURL]
                )
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        } catch {
            NSLog("Failed to write attachment: \(error)")
        }
    }
}
