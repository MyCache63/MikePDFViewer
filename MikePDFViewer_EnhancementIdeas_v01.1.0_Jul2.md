# MikePDFViewer Enhancement Ideas
v01.1.0, 2026-07-02 17:45 PT

CORRECTION + STATUS UPDATE. The v01.0.0 doc was written before a full read of the codebase, and it recommended several features the app already had (recent files menu, page rotation, two-page view, page jump, bulk image export, annotations). This version sets the record straight and marks what was actually built today.

## Built and shipped today (v6.4.0 through v6.8.0)

1. **v6.4.0 Reopen last file on launch.** Also fixed Recent PDFs so they survive an app relaunch: the app is sandboxed, and the old recents stored plain paths macOS would refuse after restart. Now they store security-scoped bookmarks. Toggle: File > Reopen Last File on Launch (default on).
2. **v6.4.1 Search debounce.** Live PDF search waits 200 ms after you stop typing before scanning the document, so big PDFs don't lag per keystroke.
3. **v6.5.0 Thumbnail size slider.** Bottom of the sidebar, small square to big square. Persisted.
4. **v6.6.0 Arrow-key paging.** Click a thumbnail, then Up/Down arrows move through pages.
5. **v6.7.0 Thumbnail right-click menu.** Export Page as PNG (300 dpi, save dialog) and Copy Page as Image (pasteboard).
6. **v6.7.1 Thumbnail pre-warm.** First 20 pages render into the cache right after open, so the sidebar is sharp immediately.
7. **v6.8.0 Make Searchable (OCR), the big one.** New toolbar button (viewfinder-with-text icon) and Tools > Make Searchable (OCR). Runs Apple's Vision OCR entirely on your Mac (free, offline, no API key) on pages that have no text, and rebuilds the PDF with an invisible text layer. After it runs, Cmd+F, text selection, and copy work on scanned documents like that FedEx label. Pages that already have text pass through untouched. Verified on a test scan: findString went from 0 matches to working.
   - Note: this complements the existing "OCR Document" button, which sends pages to an LLM (needs OpenRouter API key) and extracts text OUT as markdown. Make Searchable puts text INTO the PDF.
   - Technique adapted from the MIT-licensed mac-ocr project: https://github.com/privatenumber/mac-ocr

## Already existed before today (my earlier doc was wrong to suggest these)

- Recent PDFs menu (File > Recent PDFs)
- Page rotation (View > Rotate Right / Left, Cmd+R / Cmd+L)
- Two-page and other display modes (View > Display Mode)
- Go to Page (click "Page X of Y" in the toolbar)
- Bulk export pages as PNG/JPEG images (toolbar)
- Annotations: highlight, underline, strikethrough, sticky notes, free text, signatures, redaction
- Split view, presentation mode, watermark, password protect, merge, extract pages

## Still open for the future

- **Word-level selection polish for OCR'd scans.** Selection rectangles on OCR'd pages are close but approximate within each word. Fine for search and copy.
- **OCR'd pages lose separately-editable annotations.** Make Searchable draws existing annotations into the page (still visible, no longer movable). Annotate after OCR, not before, if you want to keep editing them.
- **Live Text-style automatic OCR on open** (background, no button press) once we trust the feature.
- **MD Quick mode find** is still best-effort (noted in code); Reader mode search is full-featured.
