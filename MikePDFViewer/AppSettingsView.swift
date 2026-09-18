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
            PerformanceSettingsTab()
                .tabItem { Label("Speed", systemImage: "speedometer") }
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

/// Launch and document-open timings, so a slow-down can be seen and compared
/// between versions instead of guessed at.
private struct PerformanceSettingsTab: View {
    @ObservedObject private var perf = PerfLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent timings")
                .font(.headline)

            if perf.events.isEmpty {
                Text("Nothing recorded yet. Open a document and come back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(perf.events.prefix(50)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.millisecondsText)
                                    .monospacedDigit()
                                    .frame(width: 66, alignment: .trailing)
                                    .foregroundStyle(event.milliseconds > 400 ? Color.orange : Color.secondary)
                                Text(event.name)
                                Text(event.detail)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(height: 200)
            }

            HStack {
                Button("Copy Timings") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(perf.summaryText(), forType: .string)
                }
                Button("Reveal Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
                }
                Spacer()
            }

            Text("Every launch and every document open is timed and written to the log, so speed can be compared from one version to the next.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Spacer()
                Button("Reveal Diagnostic Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
                }
            }
        }
        .padding(20)
    }
}
