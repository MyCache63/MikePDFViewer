# MikePDFViewer Handover - August 13, 2026

## Aug 14 - NOTE FROM THE MC3 SESSION: package build was broken, now fixed

Not your app code, and nothing you shipped was wrong. Your v6.16.x work is intact
and the app target still builds clean (verified today).

**What happened:** this repo also ships a Swift package, `MikePDFViewerKit`, built
from the same `MikePDFViewer/` folder with app-only files listed in `exclude:` in
`Package.swift`. **Mission Control 3 embeds that package** (`relativePath =
../MikePDFViewer`), so when the kit stops compiling, MC3 stops building too.

v6.16.0 added `AppSettingsView.swift` (the Cmd+, Preferences window), which
references `PresentationAppearance` defined in `PresentationView.swift`.
`PresentationView.swift` is excluded from the kit (correctly, it is app-only), but
`AppSettingsView.swift` was not, so inside the package it referenced a type that
was not in the target:

```
AppSettingsView.swift:19  cannot find 'PresentationAppearance' in scope
AppSettingsView.swift:24  incorrect argument label (have 'hexString:', expected 'named:')
AppSettingsView.swift:25  value of type 'NSColor' has no member 'hexString'
```

The app target compiled fine throughout (it has both files), which is why this was
invisible from here.

**Fix applied:** added `"AppSettingsView.swift"` to the `exclude:` list in
`Package.swift`, next to the other app-only views. Safe because the only other file
referencing it, `MikePDFViewerApp.swift`, is already excluded. Verified after the
change: MikePDFViewer app target BUILD SUCCEEDED, and MC3 BUILD SUCCEEDED.

**Rule of thumb going forward:** any new file that touches presentation mode,
settings, annotation, OCR, redaction or signatures is app-only and belongs in the
`exclude:` list. If you add a file and are unsure, run
`swift build --package-path ~/Projects/MikePDFViewer` once; it catches this in
seconds and saves MC3 from a broken build.

## Current State: v6.16.0 - True full-screen presentation + Settings window

**Branch/worktree:** `main` only, no worktrees. **BUILD:** v6.16.0 Release, installed to /Applications, not device-tested.
**Safety tag:** `before-fullscreen-presentation-2026-08-13`

### Aug 13 - v6.16.0 Full-screen presentation (Acrobat parity) + Preferences

Michael asked how to show a slide-deck PDF full screen with arrow-key advance, "consistent with Acrobat". Presentation Mode already existed (toolbar play icon) but was a `.sheet` (window-sized, not full screen), had no Escape, and leaked an `NSEvent.addLocalMonitorForEvents` that kept eating arrow keys after dismissal.

- `PresentationWindowController` (in PresentationView.swift): borderless window at the host window's screen frame, level `.mainMenu+1`, dock/menu bar hidden; level drops on `windowDidResignKey` so Cmd+Tab can't trap the user. `PresentationWindow` overrides `canBecomeKey` (borderless windows otherwise get no key events).
- Key map per Acrobat: next Right/Down/Return/PageDown/Space, prev Left/Up/Shift+Return/PageUp, Home/End, Esc or Cmd+L exits. Menu shortcut moved Shift+Cmd+P -> **Cmd+L**. Click advances, Shift+click back.
- Controls (page counter, close X) auto-fade after 2.5 s, return on mouse move; cursor hides while advancing.
- **New Settings scene (Cmd+,)**, `AppSettingsView.swift`: Presentation tab = border fill color picker (the letterbox/pillarbox fill when slide aspect != screen; default black, hex-persisted under `presentation-fill-color`), General tab = reopen-last-file, thumbnail size.

**Decisions:** borderless window + level management chosen over `toggleFullScreen` (native full screen creates a separate Space and animates ~1 s; Keynote-style is snappier) and over `enterFullScreenMode` (no clean SwiftUI overlay path). Fill color stored as hex string because Color is not AppStorage-encodable.

**Next step:** Michael device-tests v6.16.0 with Kore_Citi_Fraud_DemoReview_v01.0.1_Aug13.pdf: Cmd+L, arrows/space, Esc, then Cmd+, to change the fill color. Everything from v6.12 through v6.16 is still awaiting his device confirmation and `good-` tags.

---

## Previous: v6.15.1 - Open-speed fixes

**Branch/worktree:** `main` only, no worktrees. Working tree clean except Michael's two screenshots (left untracked on purpose).
**BUILD STATUS:** v6.15.1 builds (Release), installed to `/Applications/MikePDFViewer.app`. NOTHING since v6.9.0 is device-confirmed; no `good-` tags yet for v6.12.x-v6.15.x.
**Safety tags:** `before-open-speed-2026-08-06`, `before-print-preview-2026-07-30`, `before-notepad-2026-07-28`, `before-print-md-txt-json-2026-07-27`
**Numbers:** `OpenSpeed_BeforeAfter_v6.15.1_Aug06.md` (before/after tables)

**EXACT NEXT STEP:** Michael quits (Cmd+Q) and relaunches the app, confirms v6.15.1 under the title, then device-tests in this order: (1) open the MTN .md - should be fast, no beachball; (2) Cmd+P a long .md - Print Layout sheet with multi-page preview, fit-to-pages; (3) Notepad icon + word count; (4) hover tooltips on grayed-out icons; (5) v6.12 safety behaviors (Cmd+S on converted file routes to Save As, unsaved-changes prompts). On his confirmation: commit nothing, just tag `good-<feature>-<date>` per feature and mark here. After that, the next approved-work candidates (NOT yet approved): find-next/prev cycling in PDFs, Cmd+F in HTML/QuickLook, async EML/txt loads, window-close dirty guard, multi-window tabs.

**Decisions made (this cycle):**
- Markdown print pagination via WKWebView `printOperation` save-to-file on an offscreen window (Apple forum 705138 recipe); REJECTED slicing the single tall createPDF page into sheets (would cut text lines in half).
- Fit-to-pages implemented as CSS `html { zoom }` binary search (floor 35%); REJECTED NSPrintInfo.scalingFactor (interacts badly with fit-width pagination).
- Quick-view attributed string build deferred to on-demand (`ensureMarkdownAttributed`); REJECTED keeping it eager (0.08-1.8 s main-thread cost on every open, unused by default Reader mode).
- WebKit prewarm at launch (hidden WKWebView) to absorb the ~1.7 s first WebContent spawn.
- Tooltips: replaced SwiftUI `.help` with AppKit `NSView.toolTip` background (`.tooltip()`), because `.help` never shows on disabled controls.
- Notes stored as one pretty-printed `notes.json` in container Documents/Notes for external RAG; REJECTED per-note files (harder to index) and user-picked folder (extra sandbox bookmark complexity, can add later).
- Default app for .txt/.json set via `LSSetDefaultRoleHandlerForContentType` (`scripts/set_default_apps.swift`, already run on this Mac).

### Aug 6 - v6.15.1 Document-open lag

Michael reported lag opening documents (example: a 6 KB .md). Benchmarked the open path with the app's own sources (`scripts/benchmark_open_speed/main.swift`; compile: `swiftc -O -o benchmark main.swift MikePDFViewer/Markdown{Document,ToHTML,ReaderView,ReaderSettings,Typography,TOCSidebar,SearchController}.swift`, run with a .md path). Found: WebKit first-render ~1.7 s cold; Quick-view attributed build 0.08-1.8 s ON MAIN even though Reader mode never uses it; HTML rendered twice per open; bookmark I/O on main. Fixes: markdown load fully async; Quick-view build deferred to `ensureMarkdownAttributed()` (on switch to Quick); `MarkdownToHTML.render` memoizes last source; `RecentFilesManager.add` bookmarks on background queue; `WebKitWarmup.prewarm()` in new `applicationDidFinishLaunching`. Files: ContentView, MarkdownToHTML, MarkdownReaderView, RecentFilesManager, MikePDFViewerApp, pbxproj (6.15.1).

**Known follow-ups:** same async treatment could go to EML/txt paths; Swift-6 sendability warning on NSAttributedString capture in ensureMarkdownAttributed (harmless in Swift 5 mode).

---

## Previous (July 30)

## Current State: v6.15.0 - Markdown print preview sheet + real pagination

**BUILD STATUS:** v6.15.0 builds (Release), installed to `/Applications/MikePDFViewer.app`, awaiting device testing
**Safety tag:** `before-print-preview-2026-07-30`

### July 30 - v6.15.0 Markdown print: preview sheet, pagination fix

Michael's long .md printed as "Page 1 of 1" with microscopic text. Root cause: `HTMLToPDFRenderer` uses WKWebView `createPDF`, which returns the WHOLE document as one tall page; the print dialog then scales it to a single sheet.

- **PaginatedHTMLToPDF** (in HTMLToPDFRenderer.swift): multi-page letter PDF via WKWebView `printOperation` with a save-to-file job, `runModal` on an offscreen window (required; no panel shows). Recipe: https://developer.apple.com/forums/thread/705138
- **MarkdownToPDFConverter.convertForPrint**: paginated conversion, margins from NSPrintInfo (no @page CSS so they don't stack), CSS `html { zoom }` for text scaling.
- **MarkdownPrintSheet.swift** (new, AA00009A/9B): Cmd+P on markdown now opens a pre-print panel: live paginated preview, page count, font size 8-24 pt (default 12), margins narrow 0.3/normal 0.5/wide 1.0 in, "Fit to a page limit" 1-20 pages (binary-searches largest zoom that fits, floor 35%). Print... closes the sheet and sends the paginated PDF to the system dialog (0.4 s delay so the panel attaches to the main window).
- Settings persist via AppStorage (md-print-font-size, md-print-margin).
- NOT yet routed through the sheet: .txt/.log/.json (NSTextView path already paginates correctly; could gain the same sheet later), HTML mode, and the on-screen "Render as PDF" (still single tall page by design; candidate to switch to paginated output).

**Please test:** open a long .md, Cmd+P: sheet appears; preview shows multiple pages; change font/margins and watch it re-render; toggle Fit with 2 pages; Print... shows the system dialog with "Page 1 of N" and a readable preview.

---

## Previous (July 28)

## Current State: v6.14.1 - Notepad (JSON-backed) with word count; tooltips on disabled icons

**BUILD STATUS:** v6.14.1 builds (Release), installed to `/Applications/MikePDFViewer.app`, awaiting Michael's device testing (v6.12.x/v6.13.0 also still untested). NOTE: Michael's screenshot of July 28 9:24 PM showed a still-running v6.13.0 instance; the notepad icon only appears after a full quit (Cmd+Q) and relaunch.

### July 28 late - v6.14.1 Tooltips on disabled toolbar icons

SwiftUI `.help()` never shows while a control is disabled, so PDF-only icons (zoom, rotate, markup, ...) said nothing on hover in markdown/text mode. New `.tooltip()` modifier (AppKit `NSView.toolTip` as a `.background`, per https://blog.rampatra.com/adding-tooltips-to-swiftui-views-on-macos) replaces `.help()` on all ContentView toolbar icons and the Notepad delete button; added missing tooltips on the search-bar clear button and EML attachment Save/Open.
**Repo:** https://github.com/MyCache63/MikePDFViewer
**Latest safety tags:** `before-notepad-2026-07-28`, `before-print-md-txt-json-2026-07-27`, `before-stale-doc-artifacts-jul26`

### July 28 - v6.14.0 Notepad + word count

Michael asked for an Apple Notes style notepad (yellow lined notebook icon) with a word count function, storing notes as JSON so they can be searched/indexed/RAGed outside the app.

- **Notepad window.** Toolbar legal-pad icon (drawn in SwiftUI: yellow, ruled lines, red margin) or Tools > Notepad (Shift+Cmd+N). Left: note list with search, title (first line of the note), modified date, per-note word count. Right: editor with a text-size stepper. New-note and delete (confirmation dialog) in the window toolbar. Autosaves 0.7s after typing stops, plus on window close and app quit.
- **Word count.** Footer under the editor shows live words / characters / lines; word counting uses linguistic enumeration (`enumerateSubstrings .byWords`), Apple style. `wordCount` is also persisted per note in the JSON.
- **Storage.** `notes.json` (pretty-printed, sorted keys, ISO-8601 dates; fields: id, title, body, createdAt, modifiedAt, wordCount; top-level `version: 1`) at `~/Library/Containers/com.mikeashe.MikePDFViewer/Data/Documents/Notes/notes.json`. The footer's "notes.json" link reveals it in Finder for pointing external index/RAG tools at it.
- Fixed: `.json` was missing from the app-menu open panel (v6.13.0 only added it to ContentView's).

**Files:** `NotesStore.swift` (new, AA000096/97), `NotepadView.swift` (new, AA000098/99), `ContentView.swift`, `MikePDFViewerApp.swift`, `project.pbxproj` (6.14.0)

**Please test:** open Notepad from the toolbar icon, type a few notes (first line becomes the title), watch the live word count, quit and relaunch (notes persist), click the notes.json footer link and confirm the JSON is readable.

---

## Previous state (July 27): v6.13.0 - Print everywhere (MD/TXT/JSON/HTML) + JSON viewer + default-app for .txt/.json

### July 27 - v6.13.0 Print in every text-based viewer; .json support; default app for .txt/.json

Michael reported he could not print an .md, and asked for .json support plus making the app the default for .txt and .json.

- **Print routing.** Cmd+P and the toolbar printer button now post `.pdfPrint`; the key window's `ContentView.handlePrint()` routes by mode: PDF prints as before; Markdown renders through `MarkdownToPDFConverter` (same theme/typography as on screen) and prints the resulting PDF without leaving reader mode; TXT/LOG/JSON print through a paginating `NSTextView` forced to black-on-white (dark mode safe); HTML prints the WKWebView. QuickLook mode (docx/pptx/key) shows a hint to Convert to PDF first. Toolbar print button enables in all printable modes.
- **JSON files.** `.json` added to the open panel, routed to the plain-text viewer (monospace default, same font menu), and declared in Info.plist (`public.json`).
- **Default app.** Plain Text and JSON `LSHandlerRank` raised to Default in Info.plist, and `scripts/set_default_apps.swift` was RUN on this Mac: `public.plain-text` and `public.json` now default to com.mikeashe.MikePDFViewer (verified via `scripts/verify_default_apps.swift`). Re-run the set script on a new Mac or after a macOS reset.

**Files:** `ContentView.swift`, `MikePDFViewerApp.swift`, `Info.plist`, `project.pbxproj` (6.13.0), `scripts/set_default_apps.swift`, `scripts/verify_default_apps.swift`

**Please test:**
- Open an .md, Cmd+P: print dialog shows the themed rendering; Cancel works; reader stays on screen after.
- Open a .txt and a .json (double-click from Finder should now open MikePDFViewer), Cmd+P in each: paginated monospace output, black text even in dark mode.
- PDF printing unchanged; in a pptx/docx QuickLook view Cmd+P shows the Convert-to-PDF hint alert.
- Two windows open: Cmd+P prints only the key window's document.

**Still open from the evaluation:** v6.13 find-next/prev cycling; Cmd+F inside HTML/QuickLook; large-txt performance; v6.14 full multi-window (Cmd+N / tabs), thumbnail cache cost limits; window-close (red button) dirty guard still missing.

---

## Previous state (July 26): v6.12.5 - Stale document artifact fixes

**Diagnosis write-up:** `BugReport_StaleDocumentArtifacts_v01_Jul26.md`

### July 26 - v6.12.5 Fix stale artifacts from the previous document

Michael reported opening a file often showed leftovers from the last one (title, left thumbnails, main view), worse with more docs open. Three stacked bugs; all fixed in this patch:

1. **Key-window scoping for Open and menu commands.** `.pdfOpenFile` (File > Open, Recent, EML attachments) and other app-wide notifications were received by every `ContentView` / `PDFKitView`. Only the key window now applies them. Document-modified/saved/annotation-editing posts carry the `PDFDocument` so other windows ignore them.
2. **Thumbnail / sidebar identity reset.** Sidebar uses `.id(ObjectIdentifier(document))`. `ThumbnailItem` invalidates on document identity change (not only `documentVersion`, which reset to 0 every open). Async thumbnail completion drops stale epochs. Cache keys use full `ObjectIdentifier` instead of `hashValue`.
3. **Load generation + clear-on-open.** Every open bumps `loadGeneration` and calls `clearAllViewerState()` immediately (no more old PDF left on screen while the new one loads). Async PDF/EML/DOCX/OCR/MD-render completions check generation + URL before applying. Main pane shows a Loading state when `pdfDocument` is nil mid-open.

**Files:** `ContentView.swift`, `PDFKitView.swift`, `ThumbnailSidebar.swift`, `MikePDFViewerApp.swift`, `WatermarkSheet.swift`, `project.pbxproj` (6.12.5)

**Please test:**
- Single window: open PDF A, then B, then A again. Title, thumbnails, and main view must all match; no flash of the other file after load settles.
- Two windows: Doc A in W1, Doc B in W2; File > Open C from the key window. Only the key window becomes C; the other keeps its document and title.
- Rapid open of several large PDFs: final state matches the last chosen file only.
- PDF -> MD -> PDF and PDF -> PPTX -> PDF: no leftover thumbnails or bookmarks.
- Annotate in W1 only: W2 must not become dirty / must not change.

**Still open from the evaluation:** v6.13 find-next/prev; v6.14 full multi-window (Cmd+N / tabs) and thumbnail cache cost limits; window-close dirty guard still missing.

---

## Previous state (July 10): v6.12.4 - Safety release (data-loss fixes from the full evaluation)

### July 10 evening - v6.12 safety release

Full evaluation (two audit agents + usage review) is in `MikePDFViewer_FullEvaluation_v01.0.0_Jul10.md`; Michael said GO on the v6.12 safety slice. Shipped:

- **v6.12.0 Cmd+S corruption fix.** Save wrote the in-memory PDF to `pdfURL`, which for converted .docx/.eml/.md still points at the ORIGINAL source file, silently replacing a Word doc or email with PDF bytes. Save now writes in place only when the opened file is a real .pdf; otherwise it routes to Save As with a `.pdf`-suffixed name. All `document.write` results are checked and failures alert (previously silent).
- **v6.12.1 Unsaved-changes protection.** New `documentDirty` flag: set by `.pdfDocumentModified` (annotations, rotate, redact, page delete), `movePage`, and Make Searchable; cleared on document load and on `.pdfDocumentSaved` (new notification posted by both save paths). Opening another file while dirty shows Discard-and-Open / Cancel; quitting shows Quit Anyway / Cancel via a new `AppDelegate` (`applicationShouldTerminate`). Note: closing the WINDOW (red button) is still unguarded; quit and open-file are covered.
- **v6.12.2 Errors are visible.** DOCX/EML/MD conversion failures and unreadable PDFs now show an alert with the filename and reason (previously stored in never-displayed state vars).
- **v6.12.3 Go to Page fixed.** Cmd+G was shadowed by Find Next (which is inert for PDFs until find-cycling ships in v6.13). New View > Go to Page... menu item with Cmd+Option+G (Preview's shortcut); toolbar tooltip corrected.
- **v6.12.4 Cancellable OCR.** Make Searchable progress sheet has a Cancel button (Esc works too); `SearchableOCRService` takes a thread-safe `CancelFlag` polled between pages, throws `.cancelled`, document untouched. Also added per-page `autoreleasepool` so 300-dpi rasters don't accumulate across long scans (audit finding M3). OCR re-verified headless after refactor: scan page 0 -> 388 chars, findString works, cancel throws correctly.

**Still open from the evaluation (next slices):** v6.13 find-next/prev in PDFs + Cmd+F in HTML + print outside PDF mode + large-txt performance; v6.14 multi-window/tabs + remember-last-page + drag-drop-to-open + thumbnail cache limits + PDFDocument thread-safety. See the evaluation doc for the full ranked list.

---

## Previous state (July 10, earlier): v6.11.1 - Three new viewers: TXT, Quick Look (PPTX/DOCX), HTML

### July 10 batch - v6.9.0 through v6.11.1 (new file type viewers)

Michael asked for: .txt support (mono default, quick font change), a fast format-preserving DOCX and PPTX viewer, and an HTML viewer (mini browser). All native frameworks, no third-party dependencies.

- **v6.9.0 TXT viewer.** .txt/.text/.log open in the same NSTextView used by MD Quick mode (reused `MarkdownView`, so Cmd+F live highlight works for free). Default Menlo 13. New toolbar "textformat" menu: 7 font choices (mono listed first), bigger/smaller (also Cmd+Option+Plus/Minus), reset. Persisted in `txt-font-name` / `txt-font-size`.
- **v6.10.0 Quick Look viewer.** New `QuickLookFileView.swift` embeds `QLPreviewView` (the Finder Space-bar engine). .pptx/.ppt/.key open here instantly with native fidelity. **.docx now defaults to Quick Look too** (instant) instead of the slow NSAttributedString->HTML->WKWebView PDF conversion; a toolbar "doc.richtext" button runs the old Convert to PDF pipeline when search/annotate/print are needed. Quick Look mode has no Cmd+F (engine limitation).
- **v6.11.0 HTML mini browser.** New `HTMLBrowserView.swift`: WKWebView + `HTMLBrowserController` (ObservableObject). Back/Forward/Reload/Home toolbar buttons; links (including target=_blank and external http) navigate inside the view. Sandbox already had network.client so web links work.
- **v6.11.1** Info.plist document types added (plain text, PPTX/PPT, Keynote, HTML) so Finder "Open With" lists the app. Open panel and Recent files accept all new types.

**Testing notes for Michael:**
- Open a .txt: should be monospace; try the new "textformat" toolbar menu.
- Open a .pptx: should appear instantly, slides scrollable, formatting intact.
- Open a .docx: instant Quick Look; press the "doc.richtext" toolbar button to convert to PDF when you need annotation/search.
- Open an .html: renders like Safari; click links, use back/forward arrows in toolbar.

**Known limitations:** no Cmd+F inside Quick Look (pptx/docx quick view) - convert DOCX to PDF for search; HTML viewer has no Cmd+F yet either (can add via WKWebView.find later, same mechanic as MD Reader).

---

## Previous state (July 2, 2026): v6.8.0 - Enhancement batch (7 features in one evening)

**Prior tags:** `before-thumbnail-fix-jul2` (v6.3.0), `before-v6.4-enhancements-jul2` (v6.3.1)

### July 2 evening batch - v6.4.0 through v6.8.0

Michael approved doing all remaining enhancements. Full list with commit-per-feature in `MikePDFViewer_EnhancementIdeas_v01.1.0_Jul2.md`. Summary:

- **v6.4.0** Reopen last file on launch (File menu toggle, default on). RecentFilesManager now stores security-scoped bookmarks; without them the sandboxed app could not reopen recent files after relaunch (pre-existing bug, now fixed).
- **v6.4.1** 200 ms debounce on live PDF search (ContentView `handleSearchTextChange` -> `debouncedSearchText` -> PDFKitView).
- **v6.5.0** Thumbnail size slider at the bottom of the sidebar (`thumbnail-max-width` AppStorage).
- **v6.6.0** Up/Down arrow paging when the sidebar has focus (click a thumbnail first).
- **v6.7.0** Right-click a thumbnail: Export Page as PNG / Copy Page as Image.
- **v6.7.1** Pre-warm first 20 thumbnails after open (shared `ThumbnailRenderer` used by items and pre-warmer).
- **v6.8.0** Make Searchable (OCR): new `SearchableOCRService.swift`. On-device Apple Vision OCR rebuilds the PDF with an invisible text layer on textless pages so Cmd+F / selection / copy work on scans. Toolbar button `text.viewfinder` + Tools menu item + progress sheet. Technique adapted from MIT-licensed mac-ocr (credited in file header and commit). Verified headlessly: rasterized scan went 0 -> 388 text chars, findString matches. Distinct from the existing LLM OCRService (OpenRouter, extracts text out).

**Testing notes for Michael:**
- Quit and relaunch the app twice: second launch should reopen your last file.
- Open the FedEx label scan, press the new viewfinder toolbar button, then Cmd+F for "OMI" or the tracking number.
- After Make Searchable, press Cmd+S to keep the searchable version (it does not auto-save).

**Known limitations (documented in ideas doc):** OCR'd pages flatten annotations (still visible, not editable); word selection boxes on OCR'd pages are approximate.

### Earlier today: v6.3.1 - Sharp Retina thumbnails

Root cause of Michael's fuzzy-sidebar report: thumbnails rendered at fixed 120x160 and stretched. Now rendered at display width x Retina scale with an NSCache. Details below.

### v6.3.1 - Fix fuzzy sidebar thumbnails (July 2)

Michael reported the page previews in the left sidebar looked fuzzy. Root cause: `ThumbnailItem.generateThumbnail()` in `MikePDFViewer/ThumbnailSidebar.swift` rendered every page at a fixed 120x160 points, and SwiftUI then stretched that tiny bitmap to the full sidebar width on a Retina display (roughly a 4x upscale).

Fix, all in `ThumbnailSidebar.swift`:
- A GeometryReader now measures the actual on-screen thumbnail width, and pages render at that width times `NSScreen.backingScaleFactor` (bucketed to 64 px steps so live sidebar resizing does not re-render on every pixel of drag).
- Height is computed from the real page aspect ratio (rotation-aware) instead of assuming 120x160.
- New module-level `NSCache` keyed by document identity + page + documentVersion + pixel width, so scrolling back through the sidebar reuses already-rendered thumbnails (LazyVStack destroys off-screen rows, which previously forced a re-render on every scroll pass).
- Regeneration on documentVersion change (page move/delete) remembers the last measured width.

### Next steps / ideas
See `MikePDFViewer_EnhancementIdeas_v01.0.0_Jul2.md` for a prioritized enhancement list (recent files, thumbnail size slider, annotations, native OCR, etc). Suggested next release: v6.4.0 with Open Recent + reopen-last-document + thumbnail size slider.

---

## Previous state (May 15, 2026): v6.3.0 — GFM tables now render as real tables

**Prior safety tag:** `before-md-tables-may15` (v6.3.0 starting point)

### v6.3.0 — Pipe tables

Until v6.2.1, GFM pipe tables (`| col1 | col2 |`) rendered as a flat vertical list of paragraphs — each cell was a separate `<p>`. Root cause: `AttributedString(markdown:)` does emit table presentation intents (`table` / `tableHeaderRow` / `tableRow` / `tableCell N`), but `MarkdownToHTML.classifyBlock` ignored them and fell through to `.paragraph`.

Fix: `MarkdownToHTML.render` now detects table runs (any intent component with `case .table`), routes them into a new `TableAccumulator` that groups cells into rows and rows into tables, and emits proper `<table><thead><tbody>` HTML. Column alignments (`:---`, `:---:`, `---:`) carry through as `style="text-align:..."` on each cell.

The existing theme bundle already had GitHub/MacDown-style table CSS (borders, alternating row backgrounds, bold header) — it just had no `<table>` elements to style. With this fix, tables in your handover and plan docs now render correctly.

Applies everywhere `MarkdownToHTML` is used:
- Reader mode (WKWebView)
- Render-as-PDF
- Any host using `MarkdownToHTML.render(_:)` directly

### v6.2.1 — Fix Cmd+F doink

### v6.2.0 — Search works in MD Reader, MD Quick, PDF, DOCX, EML

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
