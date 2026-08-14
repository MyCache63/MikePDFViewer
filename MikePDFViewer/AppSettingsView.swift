import SwiftUI

/// The app's Preferences window (Cmd+,). Kept deliberately small: only
/// settings that have no natural home in a toolbar or menu live here.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            PresentationSettingsTab()
                .tabItem { Label("Presentation", systemImage: "play.rectangle") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 420)
        .padding(.vertical, 8)
    }
}

private struct PresentationSettingsTab: View {
    @AppStorage(PresentationAppearance.fillColorKey)
    private var fillHex: String = PresentationAppearance.defaultFillHex

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hexString: fillHex) ?? .black) },
            set: { fillHex = NSColor($0).hexString }
        )
    }

    var body: some View {
        Form {
            ColorPicker("Border fill color", selection: fillColorBinding, supportsOpacity: false)

            Text("Shown above and below (or left and right of) a slide when its shape doesn't match your screen, so the page keeps its proportions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Reset to Black") {
                    fillHex = PresentationAppearance.defaultFillHex
                }
            }
        }
        .padding(20)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("reopenLastDocument") private var reopenLastDocument = true
    @AppStorage("reuse-open-windows") private var reuseOpenWindows = true
    @AppStorage("thumbnail-max-width") private var thumbnailMaxWidth: Double = 200

    var body: some View {
        Form {
            Toggle("Reopen last file on launch", isOn: $reopenLastDocument)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Bring the existing window forward instead of reopening",
                       isOn: $reuseOpenWindows)
                Text("When a file is already open, opening it again raises that window rather than loading a second copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $thumbnailMaxWidth, in: 80...320) {
                    Text("Sidebar thumbnail size")
                }
                Text("\(Int(thumbnailMaxWidth)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
