# MikePDFViewer Handover — May 12, 2026

## Current State: v6.2.0 — Search works in MD Reader, MD Quick, PDF, DOCX, EML

**BUILD STATUS:** v6.2.0 builds (both `swift build` and Xcode), installed to `/Applications/MikePDFViewer.app`
**Repo:** https://github.com/MyCache63/MikePDFViewer
**Safety tags:** `before-md-search-may12` (v6.2.0 starting point), `before-md-phases-4-8-may10` (v6.1.0), `before-md-reader-may8` (v5.9.0), `before-md-docx-may4`, `before-md-render-fix-may4`, `before-eml-support-apr30`

### v6.2.0 — Cmd+F now works in every document type

Previously Cmd+F only did anything for PDF/DOCX/EML (PDFKit's `findString`). For .md files the search bar opened but did nothing. v6.2.0 wires up:

- **MD Reader (WKWebView):** New `MarkdownSearchController` (public, ObservableObject) that drives `WKWebView.find(_:configuration:)`. The app's search bar now has Prev/Next chevrons, live find as you type, Return advances, Shift+Return goes back, "No match" indicator. Same `find()` mechanic Safari uses — same highlight overlay.
- **MD Quick (NSTextView):** Two paths:
  1. `usesFindBar = true` so Cmd+F when the text view is focused opens the native macOS find bar with full prev/next/options.
  2. The app's search bar also drives the text view directly: live highlight (yellow background tint) on every match, scroll to first.
- **PDF / DOCX / EML:** Unchanged. PDFKit's existing `findString` handling continues to work.

### Public Kit API additions
- `MarkdownSearchController` (new, public, `@MainActor`, ObservableObject):
  - `find(_:caseSensitive:)`, `findNext(caseSensitive:)`, `findPrev(caseSensitive:)`, `clear()`
  - Published `lastQuery` and `lastResult` (`.idle` / `.match` / `.noMatch`)
- `MarkdownReaderView` gains optional `searchController: MarkdownSearchController?` parameter (default `nil`). Hosts that want search hold a single controller, pass it in, and call its methods from anywhere.

### v6.1.0 — Phases 4-8 of v6 plan complete

### v6.1.0 — Phases 4-8 of v6 plan complete

**Phase 4 — Typography controls.** Five orthogonal settings, all persisted via `@AppStorage`:
- Font family — System / Serif / Monospace / Quattro (iA-Writer-style)
- Font size — 11pt to 22pt slider
- Line spacing — 1.30 to 2.00 slider
- Content width — Narrow / Standard / Wide / Full Width segmented
- Paragraph gap — Tight / Normal / Loose segmented
A `textformat.size` toolbar button (visible while viewing .md in Reader mode) opens a popover with all controls plus a focus mode toggle and "Reset to Defaults" button.

**Phase 5 — Focus mode.** Same popover toggles focus mode. When on, every block-level element except the one nearest the viewport center dims to 25% opacity. Implemented via a tiny inline JS scroll observer that adds `.md-focused` class on rAF. Persisted via `@AppStorage("markdown-focus-mode")`.

**Phase 6 — TOC sidebar + reading stats.** New `MarkdownTOCSidebar` replaces the placeholder sidebar when viewing a .md in Reader mode. Shows:
- Word count
- Estimated reading time (220 wpm)
- Heading count
- Flat indented list of all headings, click any to jump (uses a `pendingScrollAnchor` binding that triggers `webView.evaluateJavaScript("location.hash = '#slug'")`)
A `list.bullet.indent`/`list.bullet` toolbar toggle hides/shows the TOC. State persisted via `@AppStorage("markdown-toc-visible")`.

**Phase 7 — Theme-aware Render-as-PDF.** `MarkdownToPDFConverter.convert(source:sourceURL:theme:typography:)` now accepts the user's current theme + typography and bakes them into the rendered PDF — exported PDFs match what's on screen.

**Phase 8 — Polish & version bump.** v5.9.0 → v6.0.0 → v6.1.0. Both `swift build` (kit) and `xcodebuild` (app) compile clean.

### v6 plan phase status (`MikePDFViewer_AddMDReader_Plan_v01_May8.md`)
- ☑ Phase 1 — Refactor to MarkdownToHTML
- ☑ Phase 2 — WKWebView reader with default theme
- ☑ Phase 3 — Theme switcher (6 themes via UserDefaults)
- ☑ Phase 4 — Typography controls
- ☑ Phase 5 — Focus mode
- ☑ Phase 6 — TOC sidebar + reading stats
- ☑ Phase 7 — Theme-aware Render-as-PDF
- ☑ Phase 8 — Polish, version bump, install

### Public Kit API (v6.1.0)
For `import MikePDFViewerKit`:
- `EmbeddedDocumentView(fileURL:markdownTheme:)` — read-only host-embeddable view (PDF/MD/DOCX/EML)
- `MarkdownReaderView(source:baseURL:theme:typography:focusMode:pendingScrollAnchor:)`
- `MarkdownReaderTheme` (.github / .newsprint / .sepia / .dark / .highContrast / .mono)
- `MarkdownTypography` + nested `FontFamily`, `ContentWidth`, `ParagraphSpacing` enums
- `TempFolderManager.baseDirectory` — host-overridable
- `DOCXToPDFConverter.convert(url:)`, `EMLToPDFConverter.convert(url:)`, `HTMLToPDFRenderer.render(html:loadExternalImages:)`
- `MarkdownToPDFConverter.convert(source:sourceURL:theme:typography:)`
- `MarkdownToHTML.render(_:) -> (html, [TOCEntry])` for hosts that want their own TOC UI

### v6.0.0 — Two big changes for one release

**1. The viewer is now also a Swift Package.** Per the design at `/Users/michaelashe/Projects/ClaudeProjectBrowserV3/MissionControlEmbeddedViewerDesignAndPlan_v01_May10.md`, the kit's reusable rendering core is exposed as `MikePDFViewerKit` (defined in `Package.swift` at the repo root). Mission Control or any other host app can `import MikePDFViewerKit` and use:
- `EmbeddedDocumentView(fileURL:markdownTheme:)` — read-only SwiftUI view that opens .pdf, .md, .markdown, .docx, .eml.
- `MarkdownReaderView(source:baseURL:theme:)` — the WKWebView-based reader, exposed directly for hosts that want more control.
- `MarkdownReaderTheme` — six built-in themes (github, newsprint, sepia, dark, highContrast, mono).
- `TempFolderManager.baseDirectory` — host-overridable scratch path. Default for the kit is `NSTemporaryDirectory/MikePDFViewerKit/`; the standalone app overrides to `~/Documents/MikePDFViewer/tmp/` (sandbox redirects to container Documents).
- `DOCXToPDFConverter.convert(url:)`, `EMLToPDFConverter.convert(url:)`, `HTMLToPDFRenderer.render(html:)` — for hosts that want lower-level access.

**Embedding contract** (kept by `EmbeddedDocumentView`): no `NotificationCenter.default.post`, no `FocusedValue`, no menu commands, no file picker, no window-level state. Two instances in the same host process are guaranteed not to interfere with each other.

The standalone `MikePDFViewer.app` continues to work unchanged. Source lives in one tree (`MikePDFViewer/`); SwiftPM excludes the app-only files (ContentView, MikePDFViewerApp, annotations, OCR, signatures, redaction, etc.).

**2. Phase 3 of the v6 plan: multi-theme reader.** The toolbar now has a paint-palette icon (visible while viewing a .md in Reader mode) that opens a theme picker:
- **GitHub** — default. Follows system light/dark.
- **Newsprint** — serif (Iowan Old Style), narrow column, warm paper background.
- **Sepia** — warm e-reader feel.
- **Dark** — always dark.
- **High Contrast** — pure black on white, larger spacing.
- **Mono** — monospace everywhere, iA-Writer-style.

Selection persists across launches (`@AppStorage("markdown-theme")`).

### v6 plan phases status (`MikePDFViewer_AddMDReader_Plan_v01_May8.md`)
- ☑ Phase 1 — Refactor to MarkdownToHTML
- ☑ Phase 2 — WKWebView reader with default theme
- ☑ Phase 3 — Theme switcher (6 themes via UserDefaults)
- ☐ Phase 4 — Typography controls (font/size/spacing/width)
- ☐ Phase 5 — Focus mode
- ☐ Phase 6 — TOC sidebar + reading stats
- ☐ Phase 7 — Theme-aware Render-as-PDF
- ☐ Phase 8 — Polish & device test

### v5.9.0 — v6 Reader MVP (Phases 1 + 2 of v6 plan)
- **Phase 1 refactor:** Extracted markdown→HTML emitter into a shared `MarkdownToHTML.swift`. Used by both `MarkdownToPDFConverter` (Render-as-PDF) and the new `MarkdownReaderView`.
- **Phase 2 Reader view:** New `MarkdownReaderView` built on WKWebView with a bundled GitHub-style CSS theme. Honors `prefers-color-scheme` so it picks light/dark from system automatically.
- **Mode toggle:** New toolbar button (book icon → Reader, doc.plaintext icon → Quick) lets you flip between the new Reader and the legacy NSTextView Quick view. Default is Reader.

### v5.9.0 — v6 Reader MVP (Phases 1 + 2 of v6 plan)
- **Phase 1 refactor:** Extracted markdown→HTML emitter into a shared `MarkdownToHTML.swift`. Used by both `MarkdownToPDFConverter` (Render-as-PDF) and the new `MarkdownReaderView`.
- **Phase 2 Reader view:** New `MarkdownReaderView` built on WKWebView with a bundled GitHub-style CSS theme. Honors `prefers-color-scheme` so it picks light/dark from system automatically. Anchor links scroll within the page; external http(s)/mailto open in default browser.
- **Mode toggle:** New toolbar button (book icon → Reader, doc.plaintext icon → Quick) lets you flip between the new Reader and the legacy NSTextView Quick view. Default is Reader.
- **Plan reference:** `MikePDFViewer_AddMDReader_Plan_v01_May8.md` — phases 3-8 still pending (themes, typography controls, focus mode, TOC sidebar, reading stats, theme-aware Render-as-PDF, polish).

### v5.8.x patch history
- **5.8.0** — Initial MD + DOCX + Open With + temp folder support.
- **5.8.1** — DOCX font scaling (1.4×) via inline-style regex; MD newline fix between blocks.
- **5.8.2** — MD anchor-link clicks (TOC `[link](#slug)`) now scroll instead of LaunchServices error -50. DOCX diagnostic dump.
- **5.8.3** — Diagnostic dump moved inside the sandbox (`~/Library/Containers/.../Data/Documents/MikePDFViewer/tmp/`) — `/tmp` writes were silently failing.
- **5.8.4** — DOCX scaling bumped to 1.8×. New CSS rule treats Word's `<p><b>line</b></p>` (plain bold lines, no Heading style) as visual headings — gives DOCX docs that lacked Heading styles a hierarchy. Diagnostic dump removed (regex confirmed working in 5.8.3 trace).

### Known sandbox quirk (mostly cosmetic)
The app is sandboxed (`com.apple.security.app-sandbox = true`). Rendered tmp PDFs land in the container's Documents (`~/Library/Containers/com.mikeashe.MikePDFViewer/Data/Documents/MikePDFViewer/tmp/`), not the user-facing `~/Documents/MikePDFViewer/tmp/` the original plan called for. Functional but not "easy for Mike to find in Finder." To fix would need either the `com.apple.security.files.documents.read-write` entitlement (Apple may flag at notarization) or a user-prompted save destination.

### v6 plan
See `MikePDFViewer_AddMDReader_Plan_v01_May8.md` (and `.docx`) for the proposed v6 work: a richer MD reader with multiple reading themes, font/spacing controls, focus mode, TOC sidebar, etc.

### v5.8 New Features: Markdown (.md) and Word (.docx) viewing + Open With
- **DOCX viewing:** Opens `.docx` files via `NSAttributedString(officeOpenXML)` → HTML → shared `HTMLToPDFRenderer` → PDFKit. All existing PDF features (search, annotations, print, etc.) work on Word docs for free.
- **Markdown quick view:** Opens `.md` and `.markdown` files with fancy Xcode-style formatting using `AttributedString(markdown:)` rendered in NSTextView. Headers, code blocks, blockquotes, inline code, bold, italic, clickable links.
- **Markdown pretty PDF:** "Render as PDF" toolbar button (doc.richtext icon, only visible when viewing .md) converts the markdown to a styled PDF via the shared HTMLToPDF pipeline. After render, prompts to save permanently (defaults to source folder + .pdf name) or keep in temp folder.
- **Open With menu:** New toolbar button + File → Open With submenu. Curated app list filtered per file type (Word/Pages/TextEdit for .docx; Xcode/VS Code/TextEdit/BBEdit for .md; Mail/Outlook for .eml; Preview/Adobe/Word/Xcode for .pdf). Only shows apps actually installed. "Other…" item invokes the system app picker. Always operates on the original source URL, never the converted tmp PDF.
- **Temp folder:** `~/Documents/MikePDFViewer/tmp/` holds rendered PDFs from .md and .docx conversions. 7-day auto-purge runs on app launch. "Clear Rendered Temp Files" item in Tools menu for manual cleanup.
- **Refactor:** Extracted `WebViewPDFRenderer` from `EMLToPDFConverter.swift` into a new shared `HTMLToPDFRenderer.swift`. EML, MD, and DOCX all share one renderer.
- **Plan:** `MikePDFViewer_AddMD_Docx_plan_v01_May4.md`

### v5.7 Feature: EML (Email) File Viewing
- Opens `.eml` files (Outlook, Gmail, Apple Mail format) the same way as PDFs
- Custom MIME parser (RFC 822/2045/2046) — no external dependencies
- Converts email to PDF via `WKWebView` print-to-PDF, then routes through existing PDFKit pipeline
- All existing PDF features (annotations, search, print, save, watermark, signatures, OCR, comparison, image export) work on emails for free
- Right-side attachments sidebar with Save/Open buttons per attachment
- "Load remote images" toggle (off by default for privacy)
- Inline images (cid:) auto-embedded as data URLs
- Plan saved as `Add_eml_to_PDFViewer_Plan_v01_April29.md`

### v5.7 New Feature: EML (Email) File Viewing
- Opens `.eml` files (Outlook, Gmail, Apple Mail format) the same way as PDFs
- Custom MIME parser (RFC 822/2045/2046) — no external dependencies
- Converts email to PDF via `WKWebView` print-to-PDF, then routes through existing PDFKit pipeline
- All existing PDF features (annotations, search, print, save, watermark, signatures, OCR, comparison, image export) work on emails for free
- Right-side attachments sidebar with Save/Open buttons per attachment
- "Load remote images" toggle (off by default for privacy)
- Inline images (cid:) auto-embedded as data URLs
- Plan saved as `Add_eml_to_PDFViewer_Plan_v01_April29.md`

### Known Issue: Gatekeeper Warning on Quarantined .eml Files

**Symptom:** When opening an `.eml` file that was downloaded from the web (e.g. a Gmail attachment saved via Edge or Chrome), macOS shows a delayed "Apple could not verify [filename] is free of malware" dialog with "Move to Trash" / "Done" buttons. The file *does* open in MikePDFViewer first; the warning appears after.

**Root cause:** Two things combined:
1. The downloaded `.eml` has a `com.apple.quarantine` extended attribute (normal for any browser-downloaded file)
2. MikePDFViewer is currently signed "Sign to Run Locally" — it's NOT notarized by Apple

When a quarantined file is opened by a non-notarized app, macOS Sequoia/Tahoe runs an async XProtect scan and pops the warning *after* the file already opened. Notarized apps (Preview, Word, Chrome, etc.) don't trigger this, which is why Mike has never seen this warning before.

**Verification:** Run `xattr -l <file>` on the offending .eml — you'll see `com.apple.quarantine: 0081;...;Edge;...` (or Chrome, Safari, etc., depending on what downloaded it). The file's actual contents are fine.

**Workarounds (don't fix the underlying issue):**
- Per file: `xattr -d com.apple.quarantine "/path/to/file.eml"` strips the flag, file opens silently next time
- Per folder: `xattr -dr com.apple.quarantine ~/Downloads` (be careful about applying to folders containing untrusted content)
- Right-click → Open in Finder gives an "Open" button on a different (less scary) dialog

**Real fixes (future work):**
1. **Notarize the app** (preferred). Requires:
   - Apple Developer Program membership ($99/yr)
   - Developer ID Application certificate
   - `xcrun notarytool submit` workflow added to the build script
   - One-time setup, ~1–2 hours. Kills the warning permanently for all files this app ever opens.
2. **Auto-strip quarantine on open** (NOT recommended for shared use). Add code in `loadEMLDocument` that calls `xattr -d com.apple.quarantine` on the URL before parsing. Loses macOS's ability to warn about genuinely malicious .eml content. Acceptable for personal use only.
3. **Add a one-shot helper script** `unquarantine.sh` that the user runs on a folder of .eml files. Less invasive than option 2 but still manual.

**Status:** Mike chose to live with the warning for now (April 30, 2026). Revisit if/when distributing the app to others or if the warning becomes annoying enough to justify notarization.

### User-Confirmed Working (v5.5–5.6)
- Printing (Cmd+P, File > Print, toolbar button)
- WYSIWYG signature: drag to move, drag corners to resize
- WYSIWYG free text: drag, resize, live text editing with font controls
- WYSIWYG sticky notes: drag to move, live text editing
- Multi-select pages (Cmd+click, Shift+click) and delete
- All 20 original features from v5.0

## What We Built

### Native macOS App — 25 Swift Files

A full-featured PDF viewer/editor built in Swift/SwiftUI using Apple's PDFKit.

**Phase 1 — Foundation**
- PDF viewing: continuous scroll, single page, two-up, two-up continuous
- Thumbnail sidebar with bookmarks section
- Search (Cmd+F), Go to Page (Cmd+G), Recent Files
- Save (Cmd+S), Save As (Shift+Cmd+S), Print (Cmd+P)
- Zoom In/Out/Fit, Dark Reading Mode, Page Rotation
- Copy selection, Share sheet
- OCR with DOCX export (Shift+Cmd+R)
- PDF Merge tool

**Phase 2 — Annotations**
- Highlight, Underline, Strikethrough (select text, then apply from toolbar)
- Sticky Notes — WYSIWYG: placed on page, drag to move, live text editing in banner
- Free Text — WYSIWYG: placed on page, drag to move, drag corners to resize, live text + font controls (family, size, bold, italic, color)
- Annotation toolbar with color picker
- Form field detection and native form filling

**Phase 3 — Page Management**
- Bookmarks with sidebar section and toggle (Cmd+D)
- Page extraction to new PDF
- Page reorder via drag-and-drop in thumbnail sidebar
- Multi-select pages (Cmd+click, Shift+click) with bulk delete

**Phase 4 — Multi-Document**
- Tab support (each window independent, Cmd+N for new window)
- Split view — same document in two panes (Opt+Cmd+2)
- Presentation mode — fullscreen, arrow keys, space bar (Shift+Cmd+P)

**Phase 5 — Advanced Annotations**
- Signature tool — draw, save, reuse. WYSIWYG placement: appears at center of page, drag to move, drag corners to resize, blue selection handles. Click any existing signature to re-edit.
- Redaction — select text → flatten to image (with confirmation dialog)
- PageRenderer shared utility for page-to-image conversion

**Phase 6 — Security & Watermark**
- Password protection: decrypt locked PDFs, encrypt with owner/user passwords
- Watermark: configurable text, font size, opacity, rotation, color

**Phase 7 — Export**
- Export pages as PNG or JPEG (72/150/300 DPI, page range selection)

**Phase 8 — Compare**
- PDF comparison: side-by-side or difference overlay, sensitivity slider

## Key Files

| File | Purpose |
|------|---------|
| `MikePDFViewerApp.swift` | App entry, menu bar (File/Edit/View/Tools), keyboard shortcuts |
| `ContentView.swift` | Main viewer, toolbar, sheet orchestration, annotation editing banner |
| `PDFKitView.swift` | `PrintablePDFView` subclass, WYSIWYG annotation editing (drag/resize), `SignatureAnnotation`, all notification handlers, print with sandbox entitlement |
| `ThumbnailSidebar.swift` | Thumbnails, bookmarks, drag-to-reorder, multi-select + delete |
| `AnnotationToolbar.swift` | Highlight/underline/strikethrough/note/text tools |
| `BookmarkManager.swift` | Persistent bookmarks per file (UserDefaults) |
| `SignatureView.swift` | Drawing canvas, save/load signatures |
| `SignatureManager.swift` | Signature persistence (UserDefaults, TIFF data) |
| `PageExtractView.swift` | Page selection grid and extract to new PDF |
| `PresentationView.swift` | Fullscreen slideshow mode |
| `PageRenderer.swift` | Shared page-to-image rendering (PNG/JPEG) |
| `RedactionService.swift` | Flatten-and-replace redaction |
| `PasswordSheet.swift` | Unlock + Encrypt sheets |
| `WatermarkService.swift` + `WatermarkSheet.swift` | Text watermark with config UI |
| `ExportImagesView.swift` | Export pages as images with format/DPI/range |
| `PDFCompareService.swift` + `PDFCompareView.swift` | Pixel-diff comparison |
| `PDFMergeView.swift` | Merge multiple PDFs |
| `OCRService.swift` + `OCRView.swift` + `DOCXExporter.swift` | AI-powered OCR + DOCX export |
| `RecentFilesManager.swift` | Recent files tracking |

## Architecture

- **WYSIWYG annotation editing**: `PrintablePDFView` subclass handles mouseDown/mouseDragged/mouseUp for drag-to-move and corner-drag-to-resize. Active annotation tracked with selection handles. Banner in ContentView shows context-appropriate controls (text field, font picker, Done/Delete).
- **Cross-view communication**: NotificationCenter for all actions. `PrintablePDFView.current` static weak ref for direct calls (print, annotation editing).
- **Tab support**: ContentView owns `@State var pdfURL` — each window is independent.
- **Print**: `com.apple.security.print` entitlement + `PrintablePDFView.performPrint()` + NSEvent Cmd+P monitor + `triggerPrint()` with view hierarchy walk fallback.
- **Thumbnail invalidation**: `documentVersion` counter increments on any mutation, triggers regeneration.
- **Type-checker workaround**: ContentView body split into `viewWithAlerts` → `viewWithNotifications` → `body` chain.
- **Undo**: All annotations use `addAnnotationWithUndo()` which registers undo actions with the window's `undoManager`.

## Build & Install

```bash
# Build
xcodebuild -project MikePDFViewer.xcodeproj -scheme MikePDFViewer -configuration Debug build

# Install (MUST delete old app first — cp -R merges instead of replacing)
rm -rf /Applications/MikePDFViewer.app
cp -R ~/Library/Developer/Xcode/DerivedData/MikePDFViewer-*/Build/Products/Debug/MikePDFViewer.app /Applications/MikePDFViewer.app
xattr -cr /Applications/MikePDFViewer.app
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/MikePDFViewer.app

# Set as default PDF app
duti -s com.mikeashe.MikePDFViewer com.adobe.pdf all
```

## Git Tags
- `v5.6` — current release, all features working
- `v5.5` — print fix confirmed working
- `before-print-fix-mar11` — safety checkpoint
- `good-basic-pdf-viewer-mar5` — v1, confirmed working

## Known Considerations
- Redaction flattens pages to images (lossy, increases file size) — user warned via confirmation dialog
- PDF Compare is pixel-based at 150 DPI — may be slow for very large pages
- Signature annotations use custom `draw(with:in:)` override — may not persist visually in all PDF readers (the stamp annotation data is saved, but the custom rendering depends on our app)
- Password encryption uses PDFKit's built-in options — standard PDF encryption
- Free text annotations with `.clear` background are transparent but won't have a visible bounding box when not selected

---

## Web Version Conversion — aiquorum.org

### What It Would Take

Converting MikePDFViewer to a web application at aiquorum.org is a significant but achievable project. Here's what's involved:

### Technology Stack

| Component | macOS (current) | Web (recommended) |
|-----------|----------------|-------------------|
| PDF rendering | Apple PDFKit | **PDF.js** (Mozilla's open-source PDF renderer) |
| UI framework | SwiftUI | **React** or **Next.js** with TypeScript |
| Annotations | PDFKit PDFAnnotation | **pdf-lib** (create/modify PDFs) + custom canvas overlay |
| Signature drawing | NSBezierPath + NSView | **HTML5 Canvas** API |
| OCR | Apple Vision framework | **Tesseract.js** (client-side) or server-side API |
| Print | NSPrintOperation | Browser `window.print()` (native) |
| File handling | Local filesystem | **File API** + drag-and-drop + cloud storage |
| Export | PDFKit + CoreGraphics | **pdf-lib** + **canvas** for image export |

### Feature-by-Feature Mapping

**Easy to port (1-2 days each):**
- PDF viewing, zoom, rotation, page navigation → PDF.js handles all of this
- Search → PDF.js has built-in text search
- Dark mode → CSS filter: `invert(1)` on the canvas
- Display modes → PDF.js supports single page, continuous scroll
- Print → `window.print()` or generate print-optimized PDF
- Bookmarks → localStorage or database
- Recent files → localStorage
- Go to page → trivial UI

**Medium effort (3-5 days each):**
- Thumbnail sidebar → Render page thumbnails via PDF.js + canvas
- Text annotations (highlight, underline, strikethrough) → Custom canvas overlay on PDF.js pages, serialize to PDF with pdf-lib
- Sticky notes / Free text → HTML overlay elements positioned over PDF pages
- Font controls for free text → Standard CSS/HTML font controls
- Signature drawing → HTML5 Canvas with mouse/touch events, save as PNG
- WYSIWYG drag/resize → HTML drag events or a library like **interact.js**
- Page reorder → Drag-and-drop UI, rebuild PDF with pdf-lib
- Page extraction → pdf-lib can create new PDFs from page subsets
- Merge PDFs → pdf-lib can combine multiple PDFs
- Export as images → Render PDF.js pages to canvas, export as PNG/JPEG blob
- Multi-select page delete → UI state + pdf-lib page removal

**Hard / requires backend (1-2 weeks each):**
- OCR → Either Tesseract.js (client-side, slower, less accurate) or a server-side endpoint using Anthropic Claude Vision API or Google Cloud Vision
- DOCX export → Server-side conversion (e.g., pandoc or python-docx), or client-side with **docx** npm package
- Password protection / encryption → pdf-lib supports basic encryption; full PDF security requires a server-side library like **qpdf** or **pikepdf**
- Redaction → Server-side: flatten page to image, rebuild PDF (same approach as native, but needs server processing for security)
- PDF comparison → Render both PDFs to canvas, pixel-diff with **pixelmatch** library (client-side feasible but CPU-intensive)
- Watermark → pdf-lib can add text watermarks to each page

**Architecture changes needed:**
- Split view → Two PDF.js instances side by side
- Presentation mode → Fullscreen API + single-page PDF.js mode
- Tab support → Browser tabs handle this natively, or use a tab UI in the app

### Estimated Effort

| Phase | Scope | Time |
|-------|-------|------|
| 1. Core viewer | PDF.js setup, navigation, zoom, search, thumbnails, dark mode, print | 1 week |
| 2. Annotations | Highlight, underline, strikethrough, sticky notes, free text with fonts, WYSIWYG drag/resize | 2 weeks |
| 3. Signatures | Drawing canvas, save/load, WYSIWYG placement on PDF | 1 week |
| 4. Page management | Reorder, extract, delete, merge, bookmarks | 1 week |
| 5. Advanced features | OCR, export images, watermark, password, comparison | 2-3 weeks |
| 6. Polish | Responsive design, mobile touch support, performance, deployment | 1 week |
| **Total** | | **8-10 weeks** |

### Key Decisions

1. **Client-side vs. server-side PDF manipulation**: pdf-lib runs entirely in the browser, which is great for privacy and speed. But some operations (OCR, redaction, heavy comparison) may need server-side processing.

2. **Annotation storage**: Two approaches:
   - **Bake into PDF**: Use pdf-lib to write annotations directly into the PDF file. Portable but slower.
   - **Overlay + export**: Store annotations as JSON, render as HTML overlays, bake into PDF only on save/export. Faster for editing.

3. **Hosting on aiquorum.org**: If AIQuorum is already a Next.js/React app, the PDF viewer could be a route/page within it. If it's a separate deployment, it could be a standalone React SPA served from a subdomain (e.g., `pdf.aiquorum.org`).

4. **Mobile support**: The web version would need touch event handling for drag/resize/signature drawing. PDF.js works on mobile browsers.

### Libraries to Use

```
pdf.js          — PDF rendering (Mozilla, battle-tested)
pdf-lib         — PDF creation/modification (annotations, merge, extract, encrypt)
interact.js     — Drag, resize, rotate gestures (optional, can use native)
tesseract.js    — Client-side OCR (optional, can use server API)
pixelmatch      — Pixel-level image comparison
file-saver      — Save files from browser
jszip           — ZIP export for batch image export
```

### What Can Be Reused

- **UX patterns**: The WYSIWYG annotation editing flow (place → drag → resize → done) translates directly
- **Signature persistence**: Same concept (draw → save as image data → reuse), just using localStorage instead of UserDefaults
- **Feature set and menu structure**: The toolbar layout and keyboard shortcuts map 1:1
- **OCR service**: If using Claude Vision API, the same approach works — send page image, get text back
- **Comparison algorithm**: Same pixel-diff approach, just using canvas + pixelmatch instead of CoreGraphics

### What Cannot Be Reused

- All Swift code (complete rewrite in TypeScript/JavaScript)
- PDFKit-specific APIs (replaced by PDF.js + pdf-lib)
- NSViewRepresentable / SwiftUI patterns (replaced by React components)
- macOS-specific features: system print dialog details, .app bundle, Dock integration, system-level default app registration
