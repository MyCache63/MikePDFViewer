# MikePDFViewer Full Evaluation
v01.0.0, 2026-07-10 (evaluation of app v6.11.1)

Method: two automated code audits (a capability matrix across all nine viewing modes, and a robustness/data-safety review), plus your actual usage evidence (the app's own recent-files list) and the pattern of enhancements you have asked for.

## 1. How you actually use the app

Your recents show the app is now your daily document hub, not just a PDF viewer: Kore client white papers and meeting-recap PDFs, an Azure value-prop .pptx (opened with the new Quick Look viewer the day it shipped), project handover.md and demo-prompt .md files, your resume, bank eStatements, and scanned shipping labels. Your window preferences show you run up to 10 windows. Your requests have consistently been about: visual quality (fuzzy thumbnails), speed (instant DOCX/PPTX), search (Cmd+F everywhere, OCR for scans), and opening more file types. That profile drives the priorities below.

## 2. What is working well

Fast format-faithful viewing across 9 modes, sharp thumbnails with caching and pre-warm, on-device OCR, full annotation suite, EML/MD/DOCX conversion pipelines, security-scoped recents with reopen-on-launch, per-mode toolbars. The foundation is good. The gaps are in consistency (features that only work in PDF mode) and data safety.

## 3. CRITICAL: fix before anything else (data safety)

These came out of the audit and two are genuine data-loss bugs:

1. **Cmd+S can destroy your original file.** When viewing a converted .docx, .eml, or rendered .md, the app holds a PDF in memory but "Save" writes that PDF's bytes over the ORIGINAL .docx/.eml/.md file, corrupting it. One accidental Cmd+S on a client Word doc and the source is gone. Fix: Save should be disabled (or become Save As with a .pdf name) whenever the on-screen document did not start life as a PDF.
2. **No unsaved-changes protection.** Annotations, OCR text layers, page deletes/moves, rotations, and redactions are all silently discarded if you open another file or quit without Cmd+S. There is no dirty flag and no "You have unsaved changes" prompt. Given you now annotate and OCR real client documents, this is the biggest everyday risk.
3. **Save failures are silent.** The write call's success flag is ignored; a full disk or read-only location looks identical to a successful save.
4. **Conversion errors are invisible.** A corrupt .docx or .eml just shows the empty "No PDF Open" screen with no message (the error text is stored but never displayed).

## 4. Broken or misleading things the audit found

5. **Cmd+G is dead.** The Edit menu binds Cmd+G to "Find Next," which shadows the Go to Page shortcut, and Find Next itself does nothing in PDF mode. Net result: Cmd+G does nothing at all in a PDF, while the toolbar tooltip still advertises it.
6. **PDF find has no next/previous.** Search highlights all matches and jumps to the first; there is no way to step through matches in a PDF (works in MD reader only).
7. **Print is PDF-only, and silently so.** In TXT/HTML/Quick Look modes the toolbar printer is disabled but Cmd+P is a silent no-op. TXT and HTML are easily printable views; Quick Look also supports printing. Nothing prints them today.
8. **Cmd+F does nothing in Quick Look and HTML modes** (silent no-op). HTML could get find easily (same WKWebView.find mechanic as MD reader). Quick Look genuinely cannot search; the honest fix is a "find is unavailable here" hint plus a Convert-to-PDF path.
9. **"Open With" offers no curated apps for .pptx/.txt/.html** (only the generic Other picker); PowerPoint/Keynote should be one click for a .pptx.

## 5. High-value functionality improvements (ranked)

10. **Multiple documents at once.** Replacing the New menu item removed macOS's New Window command, so one window = one document, and opening from Recents replaces whatever you are reading. You demonstrably work multi-window. Recommendation: restore New Window (Cmd+N), enable native window tabs, and scope the notification-based commands (open/zoom/find are broadcast to every window today) to the active window. This is the single biggest workflow upgrade, and also a prerequisite for the notification bug not biting harder.
11. **Remember the last-read page per document.** Everything reopens at page 1. Store page/scroll per file alongside the recents; reopening that 40-page white paper where you left off is a daily win.
12. **Drag and drop a file onto the window to open it.** Currently does nothing; it is the most natural open gesture on a Mac.
13. **Auto-detect scans.** When a PDF opens with no text layer, show a small banner: "This looks scanned. Make it searchable?" One click instead of knowing which toolbar icon to press.
14. **Cancellable OCR.** Make Searchable currently locks you into the run with no Cancel button; a 100-page scan means minutes of no escape.
15. **PPTX to PDF conversion path**, mirroring the DOCX Convert button, so decks become annotatable/printable/searchable when needed (doable by printing the Quick Look preview to PDF, or rendering slides via PDFKit-compatible export; needs a spike).

## 6. UI improvements

16. **Consistent capability story per mode.** Zoom, dark mode, and print buttons sit disabled (or silently dead) in most modes. Either implement per-mode equivalents (WKWebView has pageZoom; TXT has font size; Quick Look scales) or hide inapplicable buttons so the toolbar reflects reality.
17. **HTML viewer polish:** show the page title in the window subtitle, add Cmd+F (WKWebView.find), print, and an optional address display for when you click out to the web.
18. **TXT viewer polish:** word-wrap toggle and optional line numbers (useful for logs), and Cmd+Plus/Minus zoom mapped to font size.
19. **Sidebar for non-PDF modes** is just an icon and filename. Low priority, but HTML could list history and TXT could show a mini outline of long files.
20. **Match count in the search bar** ("3 of 17") once find next/prev exists.

## 7. Performance and stability (from the audit)

21. **Large .txt/.log files freeze the app**: the file is read synchronously on the main thread (twice, if not UTF-8), and worse, the entire attributed string is rebuilt on EVERY keystroke while searching. Fine at 100 KB, painful at 50 MB. Fix: background read + cache the attributed string, rebuild only on font change.
22. **OCR memory**: pages render at 300 dpi (about 34 MB each) in a loop with no autorelease pool; a long scan can balloon past a GB. Add per-page autoreleasepool and consider capping concurrent memory.
23. **Thread-safety risk**: the same PDFDocument is read simultaneously by the OCR queue, thumbnail queues, and the main view; PDFDocument is not thread-safe, so scrolling thumbnails during an OCR run is a latent intermittent crash.
24. **Thumbnail cache is unbounded** and re-caches per slider width; set a totalCostLimit so a 500-page document cannot pin a gigabyte.
25. **Deleted files linger in Recents** and open to a blank window with no explanation.

## 8. Extended functionality ideas (bigger swings, in rough value order)

26. **"Combine to PDF" across types**: select a mix of docs (pptx, docx, pdf, images, eml) and produce one PDF. You already have merge for PDFs and converters for most types; this ties them together and matches how client packets get assembled.
27. **Reduce File Size export** (downsample images via Quartz filter) for emailing large scanned PDFs.
28. **Form filling and flatten-form export.** PDFKit supports fillable forms natively; the app already counts form fields but offers no fill/flatten workflow. Bank and insurance forms would benefit.
29. **Batch OCR a folder** of scans (drop a folder, get searchable PDFs).
30. **Auto-update check** against the GitHub repo (simple version check, no framework), so installed builds do not silently go stale, which matters given your strict version discipline.

## 9. Recommended roadmap

- **v6.12 "Safety" (do first, small):** items 1-4 plus 5 (Cmd+G) and 14 (cancel OCR). Mostly guard rails; a day of work.
- **v6.13 "Find and Print everywhere":** items 6, 7, 8, 17, 20, 21.
- **v6.14 "Windows and memory":** items 10, 11, 12, 22, 23, 24.
- **v7.0 "Document hub":** items 13, 15, 26-29 as appetite allows.

My recommendation: greenlight v6.12 immediately. The Cmd+S corruption bug (item 1) is the kind that destroys a client deliverable on a bad day, and everything else in that release is cheap insurance.
