import SwiftUI

/// Floating zoom control for the bottom-right corner of the document area.
/// 100 percent means the size the document opened at, so the reset button
/// always returns to a sensible view whatever the file is.
struct ZoomControl: View {
    @Binding var zoom: Double
    var range: ClosedRange<Double> = 0.25...4.0
    let onZoomChanged: (Double) -> Void

    private var percentText: String { "\(Int((zoom * 100).rounded()))%" }

    var body: some View {
        HStack(spacing: 7) {
            Button { step(-0.1) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain)
                .help("Zoom out")

            Slider(value: $zoom, in: range)
                .controlSize(.small)
                .frame(width: 104)

            Button { step(0.1) } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .help("Zoom in")

            Text(percentText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Button { zoom = 1.0 } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain)
                .help("Back to the size it opened at")
        }
        .font(.caption)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        // Applying here keeps the main view's modifier chain small enough for
        // the Swift type-checker.
        .onChange(of: zoom) { _, newValue in onZoomChanged(newValue) }
    }

    private func step(_ delta: Double) {
        zoom = min(max(zoom + delta, range.lowerBound), range.upperBound)
    }
}
