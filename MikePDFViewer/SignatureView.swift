import SwiftUI
import PDFKit
import AppKit

struct SignatureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var signatureManager = SignatureManager()
    @State private var signatureName = "My Signature"
    let onApply: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            drawingArea
            Divider()
            savedSignatures
            Divider()
            footer
        }
        .frame(width: 500, height: 450)
    }

    @State private var drawingView = SignatureDrawingView()

    private var header: some View {
        HStack {
            Text("Signature")
                .font(.headline)
            Spacer()
            TextField("Name", text: $signatureName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding()
    }

    private var drawingArea: some View {
        VStack(spacing: 8) {
            Text("Draw your signature below")
                .font(.caption)
                .foregroundStyle(.secondary)

            SignatureCanvas(drawingView: drawingView)
                .frame(height: 120)
                .background(Color.white)
                .border(Color.gray.opacity(0.3))
                .padding(.horizontal)

            HStack {
                Button("Clear") {
                    drawingView.clear()
                }
                Spacer()
                Button("Save Signature") {
                    if let image = drawingView.getImage() {
                        let sig = SignatureManager.SavedSignature(name: signatureName, image: image)
                        signatureManager.save(sig)
                        drawingView.clear()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private var savedSignatures: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved Signatures")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(signatureManager.savedSignatures) { sig in
                        VStack(spacing: 4) {
                            if let image = sig.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 50)
                                    .background(Color.white)
                                    .border(Color.gray.opacity(0.3))
                                    .onTapGesture {
                                        onApply(image)
                                        dismiss()
                                    }
                            }
                            HStack(spacing: 4) {
                                Text(sig.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button {
                                    signatureManager.delete(sig.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 100)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: signatureManager.savedSignatures.isEmpty ? 30 : 80)

            if signatureManager.savedSignatures.isEmpty {
                Text("No saved signatures. Draw and save one above, or click Apply to use the current drawing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Apply Drawing") {
                if let image = drawingView.getImage() {
                    onApply(image)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Drawing Canvas

class SignatureDrawingView: NSView {
    private var path = NSBezierPath()
    private var isDrawing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        path.lineWidth = 2.0
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        NSColor.black.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        path.move(to: point)
        isDrawing = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let point = convert(event.locationInWindow, from: nil)
        path.line(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDrawing = false
    }

    func clear() {
        path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        needsDisplay = true
    }

    func getImage() -> NSImage? {
        guard !path.isEmpty else { return nil }
        let bounds = path.bounds.insetBy(dx: -10, dy: -10)
        guard bounds.width > 5, bounds.height > 5 else { return nil }

        let image = NSImage(size: bounds.size)
        image.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: -bounds.origin.x, yBy: -bounds.origin.y)
        transform.concat()
        NSColor.black.setStroke()
        path.stroke()
        image.unlockFocus()
        return image
    }
}

struct SignatureCanvas: NSViewRepresentable {
    let drawingView: SignatureDrawingView

    func makeNSView(context: Context) -> SignatureDrawingView {
        drawingView
    }

    func updateNSView(_ nsView: SignatureDrawingView, context: Context) {}
}
