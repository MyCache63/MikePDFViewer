import SwiftUI

struct AnnotationToolbar: View {
    @Binding var annotationColor: Color
    let onHighlight: () -> Void
    let onUnderline: () -> Void
    let onStrikethrough: () -> Void
    let onAddNote: () -> Void
    let onAddText: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Markup:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onHighlight) {
                Label("Highlight", systemImage: "highlighter")
            }
            .help("Highlight selected text")

            Button(action: onUnderline) {
                Label("Underline", systemImage: "underline")
            }
            .help("Underline selected text")

            Button(action: onStrikethrough) {
                Label("Strikethrough", systemImage: "strikethrough")
            }
            .help("Strikethrough selected text")

            Divider().frame(height: 20)

            Button(action: onAddNote) {
                Label("Note", systemImage: "note.text")
            }
            .help("Add sticky note to current page")

            Button(action: onAddText) {
                Label("Text", systemImage: "textbox")
            }
            .help("Add text box to current page")

            Divider().frame(height: 20)

            ColorPicker("", selection: $annotationColor)
                .labelsHidden()
                .frame(width: 24)
                .help("Annotation color")

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }
}
