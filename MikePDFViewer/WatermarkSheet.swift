import SwiftUI
import PDFKit

struct WatermarkSheet: View {
    let document: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var text = "CONFIDENTIAL"
    @State private var fontSize: Double = 60
    @State private var opacity: Double = 0.3
    @State private var rotation: Double = -45
    @State private var selectedColor = Color.gray

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Watermark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Text:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Watermark text", text: $text)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Font Size:")
                        .frame(width: 80, alignment: .trailing)
                    Slider(value: $fontSize, in: 20...120, step: 5)
                    Text("\(Int(fontSize))pt")
                        .frame(width: 40)
                }

                HStack {
                    Text("Opacity:")
                        .frame(width: 80, alignment: .trailing)
                    Slider(value: $opacity, in: 0.05...0.8, step: 0.05)
                    Text("\(Int(opacity * 100))%")
                        .frame(width: 40)
                }

                HStack {
                    Text("Rotation:")
                        .frame(width: 80, alignment: .trailing)
                    Slider(value: $rotation, in: -90...90, step: 5)
                    Text("\(Int(rotation))\u{00B0}")
                        .frame(width: 40)
                }

                HStack {
                    Text("Color:")
                        .frame(width: 80, alignment: .trailing)
                    ColorPicker("", selection: $selectedColor)
                    Spacer()
                }
            }

            // Preview
            previewArea

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Watermark") {
                    applyWatermark()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(height: 80)
                .shadow(radius: 2)

            Text(text)
                .font(.system(size: fontSize * 0.3, weight: .bold))
                .foregroundStyle(selectedColor.opacity(opacity))
                .rotationEffect(.degrees(rotation))
        }
        .frame(height: 80)
        .padding(.horizontal)
    }

    private func applyWatermark() {
        let config = WatermarkConfig(
            text: text,
            fontSize: CGFloat(fontSize),
            color: NSColor(selectedColor),
            opacity: CGFloat(opacity),
            rotation: CGFloat(rotation)
        )
        WatermarkService.applyWatermark(to: document, config: config)
        NotificationCenter.default.post(name: .pdfDocumentModified, object: nil)
        dismiss()
    }
}
