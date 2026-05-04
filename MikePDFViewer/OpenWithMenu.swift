import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reusable "Open With…" menu listing a curated set of installed apps that can open the
/// given file type, plus an "Other…" item that invokes the system app picker.
struct OpenWithMenu: View {
    let fileURL: URL?
    let fileKind: OpenWithFileKind

    var body: some View {
        Menu {
            menuContents
        } label: {
            Image(systemName: "arrow.up.forward.app")
        }
        .help("Open With…")
        .disabled(fileURL == nil)
    }

    /// File-menu variant: same items but rendered inside a parent menu so SwiftUI's
    /// `Menu` doesn't double-wrap the label as a button row in CommandMenu.
    @ViewBuilder
    var menuContents: some View {
        if let url = fileURL {
            ForEach(curatedApps(), id: \.self) { app in
                Button(displayName(for: app)) {
                    openIn(app: app, file: url)
                }
            }
            if !curatedApps().isEmpty {
                Divider()
            }
            Button("Other…") {
                showOtherPicker(file: url)
            }
        } else {
            Text("No file open")
        }
    }

    private func curatedApps() -> [URL] {
        OpenWithHelpers.curatedApps(for: fileKind)
    }

    private func displayName(for appURL: URL) -> String {
        OpenWithHelpers.displayName(for: appURL)
    }

    private func openIn(app: URL, file: URL) {
        OpenWithHelpers.openIn(app: app, file: file)
    }

    private func showOtherPicker(file: URL) {
        OpenWithHelpers.showOtherPicker(file: file)
    }
}

/// Static helpers shared between OpenWithMenu and the App-level File menu.
enum OpenWithHelpers {

    static func curatedApps(for kind: OpenWithFileKind) -> [URL] {
        let bundleIDs: [String]
        switch kind {
        case .pdf:
            bundleIDs = [
                "com.apple.Preview",
                "com.adobe.Acrobat.Pro",
                "com.adobe.Reader",
                "com.microsoft.Word",
                "com.apple.dt.Xcode"
            ]
        case .docx:
            bundleIDs = [
                "com.microsoft.Word",
                "com.apple.iWork.Pages",
                "com.apple.TextEdit"
            ]
        case .markdown:
            bundleIDs = [
                "com.apple.dt.Xcode",
                "com.microsoft.VSCode",
                "com.apple.TextEdit",
                "com.barebones.bbedit"
            ]
        case .eml:
            bundleIDs = [
                "com.apple.mail",
                "com.microsoft.Outlook"
            ]
        case .other:
            bundleIDs = []
        }
        return bundleIDs.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
    }

    static func displayName(for appURL: URL) -> String {
        let bundle = Bundle(url: appURL)
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return name }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String { return name }
        return appURL.deletingPathExtension().lastPathComponent
    }

    static func openIn(app: URL, file: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: cfg, completionHandler: nil)
    }

    static func showOtherPicker(file: URL) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        panel.message = "Choose an application to open \(file.lastPathComponent)"
        if panel.runModal() == .OK, let appURL = panel.url {
            openIn(app: appURL, file: file)
        }
    }
}

enum OpenWithFileKind {
    case pdf, docx, markdown, eml, other

    static func detect(url: URL) -> OpenWithFileKind {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "docx": return .docx
        case "md", "markdown": return .markdown
        case "eml": return .eml
        default: return .other
        }
    }
}
