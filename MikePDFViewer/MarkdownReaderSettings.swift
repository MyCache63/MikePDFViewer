import SwiftUI

/// Popover UI for adjusting markdown reader typography. Bound to a single
/// `MarkdownTypography` value owned by the host (typically via @AppStorage
/// in ContentView). All changes flow through the binding so updates are
/// instantaneous on screen.
struct MarkdownReaderSettings: View {
    @Binding var typography: MarkdownTypography
    @Binding var focusMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Settings")
                .font(.headline)

            Divider()

            // Font family
            HStack {
                Text("Font")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $typography.fontFamily) {
                    ForEach(MarkdownTypography.FontFamily.allCases, id: \.self) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Font size
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size")
                        .frame(width: 100, alignment: .leading)
                    Text("\(typography.fontSize)pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                }
                Slider(value: Binding(
                    get: { Double(typography.fontSize) },
                    set: { typography.fontSize = Int($0.rounded()) }
                ), in: 11...22, step: 1)
            }

            // Line height
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Line spacing")
                        .frame(width: 100, alignment: .leading)
                    Text(String(format: "%.2f", typography.lineHeight))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                }
                Slider(value: $typography.lineHeight, in: 1.30...2.00, step: 0.05)
            }

            // Content width
            HStack {
                Text("Width")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $typography.contentWidth) {
                    ForEach(MarkdownTypography.ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Paragraph spacing
            HStack {
                Text("Paragraph gap")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $typography.paragraphSpacing) {
                    ForEach(MarkdownTypography.ParagraphSpacing.allCases, id: \.self) { gap in
                        Text(gap.displayName).tag(gap)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            Toggle("Focus mode (dim non-current paragraph)", isOn: $focusMode)

            Divider()

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    typography = .default
                    focusMode = false
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
