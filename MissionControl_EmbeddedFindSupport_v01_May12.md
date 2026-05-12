**v01 — 2026-05-12 PT**

# Mission Control — Add Cmd+F to the Embedded Viewer Tab

**Repo:** `~/Projects/ClaudeProjectBrowserV3`
**Kit version:** MikePDFViewerKit v6.2.1 (no kit changes required)

---

## The problem

`EmbeddedDocumentView` is opaque — it doesn't expose a search controller. Result: in the Viewer tab, Cmd+F beeps.

## What needs to happen

Stop using `EmbeddedDocumentView` in `DocumentViewerTab`. Drive the kit's lower-level views directly so you can attach a search bar.

### Three changes to `ClaudeProjectBrowserV3`:

1. **App's `.commands`** — add an Edit-menu Find submenu (Find… / Find Next / Find Previous on Cmd+F, Cmd+G, ⇧Cmd+G). Each action posts a notification.

2. **`DocumentViewerTab`** — replace its body to dispatch by extension:
   - `.md` / `.markdown` → `MarkdownReaderView(..., searchController: mdSearch)`
   - `.pdf` → `PDFView` directly
   - `.docx` → `DOCXToPDFConverter.convert(url:)` → `PDFView`
   - `.eml` → `EMLToPDFConverter.convert(url:)` → `PDFView`

   Render a search-bar overlay on top. Listen for the three notifications.

3. **Search routing** — for MD, call `mdSearch.find/findNext/findPrev`. For PDF, use `document.findString(_:withOptions:)` → array of `PDFSelection`, advance index, call `pdfView.setCurrentSelection(_:animate:)` + `scrollSelectionToVisible(_:)`.

## Hand-off

Ready-to-paste code for all three pieces is in this same file at `git show HEAD~1:MissionControl_EmbeddedFindSupport_v01_May12.md`. Drop it on the MissionControl team (or your next Claude session in that repo) and say "apply Path A from this doc."

## Effort

~2 hours including testing. No MikePDFViewerKit changes.

## Optional follow-up (kit side)

If wiring search per-tab gets repetitive, ask MikePDFViewer to expose an `EmbeddedDocumentController` ObservableObject so hosts can drive find with one line instead of doing the dispatch themselves. Not needed for v1.
