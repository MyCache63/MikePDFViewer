**v01 — 2026-05-12 PT**

# Mission Control — Adding Cmd+F to the Embedded Viewer Tab

**From:** MikePDFViewer team (v6.2.1 kit shipping)
**To:** ClaudeProjectBrowserV3 (Mission Control)
**Status:** Instructions — apply when ready

---

## 1. The situation

You added a Viewer tab using `EmbeddedDocumentView(fileURL:)` from `MikePDFViewerKit`. It renders documents fine but Cmd+F does nothing — there's no menu item, no search bar, no responder claims the keystroke, so macOS beeps.

This is by design: **`EmbeddedDocumentView` is intentionally opaque**. It wraps either a `WKWebView` (for `.md`) or a PDFKit `PDFView` (for `.pdf` / `.docx` / `.eml`) and exposes no search affordance. Hosts that want Cmd+F need to:

1. Add Edit → Find menu items to their app commands.
2. Render their own search bar in the Viewer tab.
3. Drive the underlying search through the appropriate kit API.

This doc gives you the explicit code to do all three.

---

## 2. Two paths — pick one

### Path A (recommended) — Replace `EmbeddedDocumentView` with your own dispatch

You take over the file-type switch yourself, using lower-level kit APIs. This gives Cmd+F to **all** file types (PDF, MD, DOCX, EML).

### Path B (minimal) — Keep `EmbeddedDocumentView`, add Cmd+F for MD only

Markdown files use a side-by-side `MarkdownReaderView` instance you control; everything else still goes through `EmbeddedDocumentView` and Cmd+F is a no-op for it.

**Recommendation: Path A.** It's only ~80 lines more code and gives a consistent UX. Path B is documented below for completeness in case you want to ship Cmd+F for MD this week and tackle PDF search later.

---

## 3. Path A — Full Cmd+F support

### 3.1 Add Edit menu Find items

In `ClaudeProjectBrowserV3App.swift` (your `@main` App), add a `CommandGroup` that exposes Find / Find Next / Find Previous. These post notifications that the Viewer tab listens for.

```swift
// Inside your App's .commands { ... } closure:
CommandGroup(after: .textEditing) {
    Button("Find…") {
        NotificationCenter.default.post(name: .mcShowFind, object: nil)
    }
    .keyboardShortcut("f", modifiers: .command)

    Button("Find Next") {
        NotificationCenter.default.post(name: .mcFindNext, object: nil)
    }
    .keyboardShortcut("g", modifiers: .command)

    Button("Find Previous") {
        NotificationCenter.default.post(name: .mcFindPrev, object: nil)
    }
    .keyboardShortcut("g", modifiers: [.command, .shift])
}
```

Add the notification names in a new file or somewhere central (e.g. `MissionControlNotifications.swift`):

```swift
import Foundation

extension Notification.Name {
    static let mcShowFind  = Notification.Name("mcShowFind")
    static let mcFindNext  = Notification.Name("mcFindNext")
    static let mcFindPrev  = Notification.Name("mcFindPrev")
}
```

These names are namespaced (`mc...`) so they won't collide with the kit's internal `pdf...` notifications.

### 3.2 Replace `DocumentViewerTab` with a search-aware version

Below is a complete drop-in. Replace your existing `DocumentViewerTab` (the body shown in §4.3 of `MissionControlEmbeddedViewerDesignAndPlan_v01_May10.md`):

```swift
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import MikePDFViewerKit

struct DocumentViewerTab: View {
    let project: ProjectInfo

    @State private var selectedURL: URL?

    // Loaded document state — only one of these is non-nil at a time
    @State private var pdfDocument: PDFDocument?
    @State private var markdownSource: String?
    @State private var loadError: String?
    @State private var isLoading: Bool = false

    // Search state
    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @StateObject private var mdSearch = MarkdownSearchController()
    @State private var pdfSelections: [PDFSelection] = []
    @State private var pdfSelectionIndex: Int = -1

    // PDF view reference for driving findString / setCurrentSelection.
    // Held as an ObservableObject so the SwiftUI representable can populate it.
    @StateObject private var pdfRef = PDFViewRef()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                content
                if showSearch && selectedURL != nil {
                    searchBar
                }
            }
        }
        // Receive Edit menu commands. Active tab only — when the user is on
        // another tab, the view is removed from the hierarchy and stops receiving.
        .onReceive(NotificationCenter.default.publisher(for: .mcShowFind)) { _ in
            handleShowFind()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcFindNext)) { _ in
            handleFindNext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcFindPrev)) { _ in
            handleFindPrev()
        }
        .onChange(of: selectedURL) { _, newValue in
            // Reset search when the document changes
            showSearch = false
            searchText = ""
            mdSearch.clear()
            pdfSelections = []
            pdfSelectionIndex = -1
            if let url = newValue {
                Task { await load(url) }
            } else {
                pdfDocument = nil
                markdownSource = nil
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            if let url = selectedURL {
                Text(url.lastPathComponent).font(.caption.weight(.semibold))
                Spacer()
                Button("Find") { showSearch.toggle() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .keyboardShortcut("f", modifiers: .command)
                Button("Open in MikePDFViewer") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Text("No document selected").foregroundStyle(.secondary)
                Spacer()
            }
            Button("Choose…") { pickFile() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Document content

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36))
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let source = markdownSource {
            MarkdownReaderView(
                source: source,
                baseURL: selectedURL,
                searchController: mdSearch
            )
        } else if let doc = pdfDocument {
            PDFViewWrapper(document: doc, ref: pdfRef)
        } else if selectedURL == nil {
            Text("Pick a document from this project to view inline")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Search bar overlay

    @ViewBuilder
    private var searchBar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find in document…", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                        .onChange(of: searchText) { _, newValue in
                            performLiveSearch(newValue)
                        }
                        .onSubmit { handleFindNext() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    Button { handleFindPrev() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty)
                    Button { handleFindNext() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty)
                    if pdfDocument != nil && !searchText.isEmpty {
                        Text("\(matchIndicator)")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button { closeSearch() } label: {
                        Text("Done").font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(8)
                .shadow(radius: 4)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    private var matchIndicator: String {
        guard !pdfSelections.isEmpty else { return "No match" }
        return "\(pdfSelectionIndex + 1) of \(pdfSelections.count)"
    }

    // MARK: - Find command handlers

    private func handleShowFind() {
        guard selectedURL != nil else { return }
        showSearch.toggle()
        if !showSearch { closeSearch() }
    }

    private func closeSearch() {
        showSearch = false
        searchText = ""
        mdSearch.clear()
        pdfSelections = []
        pdfSelectionIndex = -1
        pdfRef.view?.highlightedSelections = nil
        pdfRef.view?.setCurrentSelection(nil, animate: false)
    }

    private func performLiveSearch(_ query: String) {
        if let _ = markdownSource {
            if query.isEmpty { mdSearch.clear() } else { mdSearch.find(query) }
        } else if let doc = pdfDocument {
            pdfSelections = doc.findString(query, withOptions: .caseInsensitive)
            pdfSelectionIndex = pdfSelections.isEmpty ? -1 : 0
            updatePDFSelectionDisplay()
        }
    }

    private func handleFindNext() {
        if markdownSource != nil {
            mdSearch.findNext()
        } else if !pdfSelections.isEmpty {
            pdfSelectionIndex = (pdfSelectionIndex + 1) % pdfSelections.count
            updatePDFSelectionDisplay()
        }
    }

    private func handleFindPrev() {
        if markdownSource != nil {
            mdSearch.findPrev()
        } else if !pdfSelections.isEmpty {
            pdfSelectionIndex = (pdfSelectionIndex - 1 + pdfSelections.count) % pdfSelections.count
            updatePDFSelectionDisplay()
        }
    }

    private func updatePDFSelectionDisplay() {
        guard let view = pdfRef.view, pdfSelectionIndex >= 0,
              pdfSelectionIndex < pdfSelections.count else { return }
        let sel = pdfSelections[pdfSelectionIndex]
        view.highlightedSelections = pdfSelections
        view.setCurrentSelection(sel, animate: true)
        view.scrollSelectionToVisible(nil)
    }

    // MARK: - File loading

    private func load(_ url: URL) async {
        await MainActor.run {
            isLoading = true
            loadError = nil
            pdfDocument = nil
            markdownSource = nil
        }
        do {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pdf":
                if let doc = PDFDocument(url: url) {
                    await MainActor.run { self.pdfDocument = doc; self.isLoading = false }
                } else {
                    await MainActor.run { self.loadError = "Could not open PDF"; self.isLoading = false }
                }
            case "md", "markdown":
                let source = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { self.markdownSource = source; self.isLoading = false }
            case "docx":
                let (doc, _) = try await DOCXToPDFConverter.convert(url: url)
                await MainActor.run { self.pdfDocument = doc; self.isLoading = false }
            case "eml":
                let doc = try await EMLToPDFConverter.convert(url: url)
                await MainActor.run { self.pdfDocument = doc; self.isLoading = false }
            default:
                await MainActor.run { self.loadError = "Unsupported file type: .\(ext)"; self.isLoading = false }
            }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription; self.isLoading = false }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.pdf]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let eml = UTType(filenameExtension: "eml") { types.append(eml) }
        panel.allowedContentTypes = types
        panel.directoryURL = URL(fileURLWithPath: project.path)
        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
        }
    }
}

// MARK: - PDFView wrapper that exposes a ref for find operations

final class PDFViewRef: ObservableObject {
    weak var view: PDFView?
}

struct PDFViewWrapper: NSViewRepresentable {
    let document: PDFDocument
    let ref: PDFViewRef

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        ref.view = v
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        ref.view = nsView
    }
}
```

### 3.3 What you no longer need

Once you've replaced `DocumentViewerTab` with the version above, **you can stop using `EmbeddedDocumentView` from `MikePDFViewerKit` entirely** — you're now driving `MarkdownReaderView` and `PDFView` directly. The other kit symbols you still use:
- `MarkdownReaderView`
- `MarkdownSearchController`
- `DOCXToPDFConverter`
- `EMLToPDFConverter`
- (optionally) `MarkdownReaderTheme`, `MarkdownTypography` if you want to expose those

---

## 4. Path B — Cmd+F for markdown only (minimal change)

If you want to ship search this week and tackle PDF search later, keep `EmbeddedDocumentView` for everything except `.md`. For `.md` files, render `MarkdownReaderView` directly so you can attach a `MarkdownSearchController`.

Inside `DocumentViewerTab`'s body:

```swift
if let url = selectedURL {
    let ext = url.pathExtension.lowercased()
    if ext == "md" || ext == "markdown" {
        // Render MarkdownReaderView directly so we can drive Find
        if let source = markdownSource {
            ZStack {
                MarkdownReaderView(source: source, baseURL: url, searchController: mdSearch)
                if showSearch { searchBar }
            }
        } else {
            ProgressView().task { try? loadMarkdown(url) }
        }
    } else {
        // PDF / DOCX / EML: keep using the opaque view; no Find yet.
        EmbeddedDocumentView(fileURL: url)
    }
}
```

`mdSearch`, `showSearch`, `searchText`, and the `searchBar` view are the same as in Path A. Skip all the PDFView wiring.

---

## 5. Edge cases & gotchas

1. **Notification scope.** The notifications you defined (`.mcShowFind` etc.) are global. If you later add another tab that wants its own Find behavior, you'll either need to namespace per tab or use `@FocusedValue` to route Find to whichever tab is on top.

2. **PDFView's built-in find UI.** PDFKit has its own undocumented Find machinery (`PDFView.performAction(_:)` with hidden constants). Don't bother — the public `findString` API used above is the supported path.

3. **`MarkdownSearchController.lastResult` is `@Published`.** If you want a "No match" indicator for MD files (like the PDF "1 of 5" indicator), bind to `mdSearch.lastResult` and check for `.noMatch`.

4. **Selection persistence.** When the user closes the search bar, PDFView keeps the last `currentSelection` highlighted. `closeSearch()` calls `setCurrentSelection(nil, animate: false)` and clears `highlightedSelections` so the document looks pristine again.

5. **Escape key.** The current code doesn't bind ⎋ to close the search bar. Add `.onExitCommand { closeSearch() }` to `searchBar` if you want Esc-to-dismiss.

6. **First responder for the TextField.** SwiftUI's `@FocusState` will move focus into the search field when it appears. Add this if you want the textfield to receive focus automatically:
    ```swift
    @FocusState private var searchFocused: Bool
    // on the TextField:
    .focused($searchFocused)
    // in handleShowFind() after showSearch = true:
    DispatchQueue.main.async { searchFocused = true }
    ```

---

## 6. What MikePDFViewerKit could do to make this simpler (future)

If you find yourself doing this same wiring in other tabs (e.g. a side-panel viewer in the File Browser), it'd be worth asking the MikePDFViewer team to expose:

- **`EmbeddedDocumentController`** — an `ObservableObject` you'd hold once per `EmbeddedDocumentView`. Methods: `showFind()`, `findNext()`, `findPrev()`, `clearFind()`. Internally it routes to the right backend (MarkdownSearchController for MD, PDFView selection cursor for PDF).
- **Built-in search bar overlay** — `EmbeddedDocumentView` would render its own bar when the controller's `isFindActive` is true.

That would collapse all of §3.2 to:

```swift
@StateObject private var docCtrl = EmbeddedDocumentController()

EmbeddedDocumentView(fileURL: url, controller: docCtrl)
    .onReceive(NotificationCenter.default.publisher(for: .mcShowFind)) { _ in
        docCtrl.showFind()
    }
```

If/when you'd like that, file the request against the MikePDFViewer repo and we'll add it as a v6.3.0 or v6.2.2 patch.

---

## 7. Verification

After applying Path A, open the Viewer tab and:

- [ ] Pick a `.md` file. Cmd+F opens the search bar. Type a word. Up/down chevrons step through matches. Esc closes (if you wired ⎋).
- [ ] Pick a `.pdf` file. Same — but you'll also see "1 of N" between the search field and chevrons.
- [ ] Pick a `.docx` file. Converted to PDF internally; search works like a PDF.
- [ ] Pick a `.eml` file. Same as DOCX.
- [ ] Edit menu shows **Find…**, **Find Next**, **Find Previous** at the standard shortcuts.
- [ ] Switch tabs while search is open — search resets when you come back.
- [ ] Standalone MikePDFViewer.app still works (separate process; unaffected).

---

## 8. Effort estimate

- Path A: ~2 hours including testing.
- Path B: ~30 minutes.

Both build cleanly against `MikePDFViewerKit` v6.2.1 — no kit changes required.
