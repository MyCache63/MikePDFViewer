import SwiftUI
import PDFKit
import AppKit

struct SignatureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var signatureManager = SignatureManager()
    @State private var signatureName = "My Signature"
    let onApply: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Title
            Text("Signature")
                .font(.headline)
                .padding(.top, 16)

            // Drawing canvas
            VStack(spacing: 6) {
                Text("Draw your signature below:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SignatureCanvas(drawingView: drawingView)
                    .frame(height: 100)
                    .background(Color.white)
                    .border(Color.gray.opacity(0.4))
                    .padding(.horizontal, 16)

                HStack {
                    Button("Clear") {
                        drawingView.clear()
                    }
                    .controlSize(.small)

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("Name", text: $signatureName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)

                        Button("Save") {
                            if let image = drawingView.getImage() {
                                let sig = SignatureManager.SavedSignature(name: signatureName, image: image)
                                signatureManager.save(sig)
                                drawingView.clear()
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider().padding(.horizontal, 16)

            // Saved signatures
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved Signatures")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                if signatureManager.savedSignatures.isEmpty {
                    Text("No saved signatures. Draw one above and click Save.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(signatureManager.savedSignatures) { sig in
                                savedSignatureCard(sig)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 90)
                }
            }

            Divider().padding(.horizontal, 16)

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Current Drawing") {
                    if let image = drawingView.getImage() {
                        onApply(image)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 480, height: 400)
    }

    @State private var drawingView = SignatureDrawingView()

    private func savedSignatureCard(_ sig: SignatureManager.SavedSignature) -> some View {
        VStack(spacing: 4) {
            if let image = sig.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 36)
                    .background(Color.white)
                    .border(Color.gray.opacity(0.3))
            }
            Text(sig.name)
                .font(.caption2)
                .lineLimit(1)
            HStack(spacing: 6) {
                Button("Use") {
                    if let image = sig.image {
                        onApply(image)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

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
