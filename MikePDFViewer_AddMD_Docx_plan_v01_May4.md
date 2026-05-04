# MikePDFViewer — Add Markdown & DOCX Viewing

**Plan version:** v01 — 2026-05-04
**Author:** Claude (with Mike)
**Target app version:** v5.8

---

## 1. Goals

Add native viewing for `.md` and `.docx` files inside MikePDFViewer, alongside the existing PDF and EML support. Mike's confirmed choices:

| # | Decision |
|---|----------|
| 1 | DOCX viewed via **convert-to-PDF pipeline** (same approach as EML — reuses PDFKit, search, thumbnails, annotations). |
| 2 | Markdown "pretty" mode rendered as **MD → HTML → PDF** (no pandoc / no external binaries). |
| 3 | Temp output folder: **`~/Documents/MikePDFViewer/tmp/`** (visible in Finder, easy to clean up). |
| 4 | Plain `.md` mode: **fancy rendered (Xcode-style)** using `AttributedString(markdown:)` — *not* raw monospace. |
| 5 | "Open With": **both toolbar button and File menu**, with **standard macOS Open With submenu plus a curated short list** (Word, TextEdit, Xcode, VS Code, etc.). |

### Non-goals (explicitly out of scope for v5.8)
- Editing .md or .docx files inside the app.
- True MD → DOCX conversion (rejected: requires pandoc bundle, ~150 MB).
- Live preview while a .md file changes on disk.
- Syntax highlighting in code blocks beyond what `AttributedString` provides.
- Reading legacy `.doc` (Word 97-2003) — only `.docx` (Office Open XML).

---

## 2. User flows

### Flow A — Open a .md file (default: fancy quick view)

1. User double-clicks `report.md` in Finder, or uses **File → Open PDF or Email/Markdown/Word…**
2. App detects `.md` extension, parses the file as UTF-8 text.
3. Renders into a SwiftUI `ScrollView` containing `Text(AttributedString(markdown:))` styled with custom CSS-like formatting:
   - Headings: bold, larger sizes per level
   - `code` and ```code blocks```: monospace, light grey background
   - Lists: indented with bullets/numbers
   - Links: blue, clickable (open in default browser)
   - `---` rules: horizontal divider
   - Quote blocks: left bar + italic
4. A toolbar button **"Render as PDF"** lets the user upgrade to the pretty PDF view (Flow B).

### Flow B — Open .md as PDF (pretty mode, on-demand)

1. From Flow A, user clicks **"Render as PDF"** (or chooses **File → Open As → PDF…** when picking the file).
2. App converts MD → HTML (basic CSS styling baked in) → renders to PDF via `WKWebView.createPDF` (same renderer used for EML).
3. Saves intermediate PDF to `~/Documents/MikePDFViewer/tmp/<basename>_<timestamp>.pdf`.
4. Loads the PDF into the existing PDFKit viewer — gets search, page thumbnails, zoom, print, annotation, etc.
5. After PDF renders, app presents a **"Save PDF…"** prompt:
   - **Save** → moves file out of tmp to a user-chosen location.
   - **Keep in tmp** → file stays in tmp folder (auto-cleaned on next launch if older than 7 days).

### Flow C — Open a .docx file

1. User opens `Letter.docx` from Finder or **File → Open**.
2. App reads the file via `NSAttributedString(url:options:[.documentType:.officeOpenXML])`.
3. Converts the `NSAttributedString` to HTML, then HTML → PDF via WKWebView (same pipeline).
4. PDF is saved in `~/Documents/MikePDFViewer/tmp/`, opened in PDFKit viewer.
5. Same "Save PDF…" prompt as Flow B.

### Flow D — "Open With" another app

When viewing any document type, three entry points:

1. **Toolbar button** (folder-with-arrow icon) → dropdown menu.
2. **File → Open With ▸** submenu.
3. **Right-click context menu** on the document area.

Each menu shows:

```
Open With
├── Microsoft Word           (curated, only if installed)
├── TextEdit                 (curated, always present on macOS)
├── Xcode                    (curated, only if installed)
├── Visual Studio Code       (curated, only if installed)
├── Pages                    (curated, only if installed)
├── ─────────────────
└── Other…                   (opens system "Choose Application" picker)
```

The curated list is filtered per file type (e.g., Word is hidden for .md, Xcode is hidden for .docx). The "Other…" item invokes `NSOpenPanel` configured to pick an `.app`, then calls `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`.

For .md files in Flow A or B, "Open With" passes the **original .md path**, not the rendered tmp PDF.
For .docx files in Flow C, "Open With" passes the **original .docx path**.

---

## 3. Architecture

### 3.1 File-type dispatch

Extend the existing `loadDocument(from:)` switch in `ContentView.swift` to recognize four extensions:

```
.pdf  → loadPDFDocument(from:)            (existing)
.eml  → loadEMLDocument(from:)            (existing)
.md   → loadMarkdownDocument(from:)       (NEW — Flow A)
.docx → loadDOCXDocument(from:)           (NEW — Flow C)
```

A new `MarkdownView` SwiftUI component renders the AttributedString quick view (Flow A). When user clicks "Render as PDF", the same converter used by Flow C handles MD → HTML → PDF.

### 3.2 Conversion pipeline (shared with EML)

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│  .md  /  .docx  │  ───▶ │      HTML       │  ───▶ │      PDF        │
└─────────────────┘       └─────────────────┘       └─────────────────┘
        │                         │                         │
        │                  WKWebView render          PDFDocument loaded
   Source file              + CSS styling             into PDFKit view
```

This re-uses `WebViewPDFRenderer` from `EMLToPDFConverter.swift`. We extract it into a shared helper (`HTMLToPDFRenderer.swift`) so EML, MD, and DOCX all share it.

### 3.3 NSAttributedString for DOCX → HTML

macOS's built-in DOCX reader:

```swift
let attrStr = try NSAttributedString(
    url: docxURL,
    options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
    documentAttributes: nil
)

// Convert to HTML
let htmlData = try attrStr.data(
    from: NSRange(location: 0, length: attrStr.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
)
let html = String(data: htmlData, encoding: .utf8) ?? ""
```

Then feed `html` to `HTMLToPDFRenderer.render(html:)`. macOS handles paragraphs, fonts, basic tables, images, lists. Complex DOCX features (embedded charts, footnotes) may not survive; that's an acceptable v5.8 limitation.

### 3.4 Markdown → HTML

`AttributedString(markdown:)` parses GitHub-flavoured Markdown to an `AttributedString` we can render directly (Flow A). For Flow B (rendered PDF), we wrap it in a styled HTML template with CSS so headings, code blocks, lists look "Xcode-like":

```html
<!DOCTYPE html><html><head><style>
  body { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 13pt; line-height: 1.55; padding: 0.5in; }
  h1, h2, h3 { color: #1a1a1a; margin-top: 1.2em; }
  code { font-family: "SF Mono", Menlo, monospace; background: #f4f4f4; padding: 1px 4px; border-radius: 3px; }
  pre { background: #f4f4f4; padding: 12px; border-radius: 4px; overflow-x: auto; }
  blockquote { border-left: 3px solid #888; padding-left: 12px; color: #555; font-style: italic; }
  table { border-collapse: collapse; }
  th, td { border: 1px solid #ccc; padding: 4px 8px; }
  a { color: #0a5cc4; }
  hr { border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }
</style></head><body>
  {{ rendered MD content }}
</body></html>
```

`AttributedString` natively handles: headings, bold, italic, links, inline code, lists. For fenced code blocks and tables, we'll do a small pre-processing pass on the raw MD text before passing it through. (See "Open questions" for limits.)

### 3.5 Open With

A reusable SwiftUI menu component `OpenWithMenu` takes:
- `fileURL: URL` — the file to open
- `fileType: FileType` — to filter the curated list

Implementation:

```swift
private func curatedApps(for type: FileType) -> [URL] {
    let candidates: [String: [String]] = [
        .docx: ["com.microsoft.Word", "com.apple.TextEdit", "com.apple.iWork.Pages"],
        .md:   ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.TextEdit"]
    ]
    return (candidates[type] ?? []).compactMap {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }
}

private func openIn(app: URL, file: URL) {
    let cfg = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([file], withApplicationAt: app, configuration: cfg)
}

private func showOtherPicker(file: URL) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if panel.runModal() == .OK, let appURL = panel.url {
        openIn(app: appURL, file: file)
    }
}
```

---

## 4. New files

| File | Purpose |
|------|---------|
| `MarkdownDocument.swift` | Lightweight wrapper holding raw text + parsed `AttributedString`. |
| `MarkdownView.swift` | SwiftUI view rendering AttributedString (Flow A "quick view"). |
| `MarkdownToPDFConverter.swift` | MD → HTML → PDF (Flow B). |
| `DOCXToPDFConverter.swift` | DOCX → NSAttributedString → HTML → PDF (Flow C). |
| `HTMLToPDFRenderer.swift` | **Refactored out of `EMLToPDFConverter`** — shared WKWebView PDF renderer. |
| `TempFolderManager.swift` | Owns `~/Documents/MikePDFViewer/tmp/`. Creates folder on first use, cleans files older than 7 days on app launch. |
| `OpenWithMenu.swift` | Reusable SwiftUI menu (toolbar + File menu + context menu). |

## 5. Modified files

| File | Change |
|------|--------|
| `ContentView.swift` | Add `loadMarkdownDocument(from:)` and `loadDOCXDocument(from:)`; add MarkdownView branch in main view; wire `OpenWithMenu` into toolbar. |
| `MikePDFViewerApp.swift` | Update `openPDF()` panel allowed types to include `.md` and `.docx`; rename menu item to **"Open File…"**; add **File → Open With** submenu. |
| `Info.plist` | Add CFBundleDocumentTypes entries for `public.plain-text`/`net.daringfireball.markdown` and `org.openxmlformats.wordprocessingml.document`. |
| `EMLToPDFConverter.swift` | Strip out the WebViewPDFRenderer class; call `HTMLToPDFRenderer` instead. |
| `MikePDFViewer.xcodeproj/project.pbxproj` | Register all 7 new files; bump `MARKETING_VERSION` 5.7 → 5.8. |
| `handover.md` | Update with v5.8 status when complete. |

---

## 6. Phases

### Phase 1 — Refactor (low risk)
- Extract `HTMLToPDFRenderer` from `EMLToPDFConverter`.
- Verify EML viewing still works identically.
- Commit + tag.

### Phase 2 — DOCX viewing
- Add `DOCXToPDFConverter`, `TempFolderManager`.
- Wire `.docx` extension into `ContentView.loadDocument(from:)`.
- Update `Info.plist` UTI registration.
- Test on a few real .docx samples (Word-saved, Pages-exported, Google Docs export).
- Commit `[builds, not device-tested]`, install to /Applications, ask Mike to test.

### Phase 3 — Markdown quick view (Flow A)
- Add `MarkdownDocument`, `MarkdownView`.
- Wire `.md` extension.
- Commit + install + test.

### Phase 4 — Markdown pretty PDF (Flow B)
- Add `MarkdownToPDFConverter`.
- Add toolbar button "Render as PDF" inside MarkdownView.
- Add "Save PDF…" prompt after render.
- Commit + install + test.

### Phase 5 — Open With
- Add `OpenWithMenu`.
- Wire into ContentView toolbar, File menu, right-click.
- Test curated list with Word installed and not installed (graceful degradation).
- Commit + install + test.

### Phase 6 — Polish
- Test edge cases: huge .md (10k lines), .docx with embedded images, broken/corrupt files.
- Verify tmp folder auto-cleanup runs on launch.
- Update About box version stamp to 5.8.
- Update handover.md.
- Final commit + push, tag `good-md-docx-may4`.

---

## 7. Temp folder lifecycle

**Path:** `~/Documents/MikePDFViewer/tmp/`

**Filenames:** `<original-basename>_<yyyyMMdd-HHmmss>.pdf`
e.g. `Humana_RFP_20260504-141207.pdf`

**Creation:** Lazy — folder is created on first use via `TempFolderManager.ensureTempFolder()`.

**Cleanup policy:**
- On app launch, delete any file in tmp older than 7 days.
- After "Save PDF…" the file is *moved* (not copied) out of tmp.
- "Clear Temp Files" menu item under **Tools** menu — manual purge.

**Why visible (not `~/Library/Caches`)**: per Mike's choice. He can browse it in Finder, copy out anything useful, see if disk is being eaten.

---

## 8. Open questions / risks

1. **Markdown table rendering:** `AttributedString(markdown:)` does not render tables in Flow A. For Flow B (PDF) we'll do a small regex-based pre-pass to convert `| col | col |` syntax to `<table>` HTML. **Risk:** complex tables with alignment may render poorly. *Mitigation:* document the limit; user can always fall back to Open With → VS Code.

2. **DOCX with embedded images:** `NSAttributedString` extracts inline images as `NSTextAttachment`. When converting to HTML, these become base64-embedded `<img>` tags — should work in our pipeline. **Risk:** very large embedded images could blow PDF rendering memory. *Mitigation:* cap at 25 MB total image data; warn on overflow.

3. **DOCX track changes / comments:** Won't be rendered. Acceptable for v5.8.

4. **Markdown extensions (mermaid, math, footnotes):** Not supported. Acceptable.

5. **Filename collisions in tmp folder:** Timestamp suffix (`_HHmmss`) makes collision unlikely. If two opens happen in the same second, append `_1`, `_2`.

6. **Should the "Render as PDF" button auto-trigger** for .md files instead of showing the quick view first? **Decision:** No — quick view loads instantly (no WKWebView spin-up), so it's the better default. User has to explicitly request the heavier PDF render.

7. **Save dialog default location** for "Save PDF…" — same folder as the source .md/.docx? Or always Downloads? **Decision:** same folder as source, with original basename + ".pdf".

8. **"Open With" for the original .md inside the in-app render**: the menu must pass `originalMDURL`, not the tmp PDF path. Implementation needs both paths plumbed through.

---

## 9. Effort estimate

| Phase | Estimate |
|-------|----------|
| 1 — Refactor | 30 min |
| 2 — DOCX | 1.5 h |
| 3 — MD quick | 1 h |
| 4 — MD pretty | 1 h |
| 5 — Open With | 1.5 h |
| 6 — Polish | 1 h |
| **Total** | **~6.5 h** of Claude work, plus Mike testing each phase. |

---

## 10. Success criteria

- ✅ Mike double-clicks a `.md` from Finder and it opens in MikePDFViewer with fancy formatting.
- ✅ Mike double-clicks a `.docx` and it opens as a PDF in MikePDFViewer.
- ✅ "Render as PDF" turns a markdown view into a printable, search-able PDF.
- ✅ "Save PDF…" exports the rendered PDF to a chosen location.
- ✅ "Open With" → Word launches Word with the original .docx.
- ✅ "Open With" → Xcode launches Xcode with the original .md.
- ✅ Temp folder doesn't grow unboundedly.
- ✅ Existing PDF + EML viewing still works (no regression).
- ✅ Version stamp shows v5.8 in About box.
