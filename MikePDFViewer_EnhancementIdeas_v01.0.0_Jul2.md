# MikePDFViewer Enhancement Ideas
v01.0.0, 2026-07-02 17:15 PT

Recommendations gathered while fixing the fuzzy sidebar thumbnails (shipped in v6.3.1). Grouped by area, with the ones I'd do first marked QUICK WIN.

## Speed

1. **Thumbnail cache (DONE in v6.3.1).** Thumbnails are now cached per page, size, and document version, so scrolling the sidebar no longer re-renders pages it already drew.
2. **QUICK WIN: Pre-warm thumbnails for the first ~20 pages** in the background right after a document opens, instead of waiting for each row to scroll into view. Opening a long PDF would feel instant in the sidebar.
3. **Debounce live search.** If typing in the search bar on a large PDF ever feels laggy, add a 150 ms debounce before running `findString`. Only worth doing if you actually feel lag.

## Functionality

4. **QUICK WIN: Recent Files menu (File > Open Recent).** The app currently forgets what you had open. NSDocumentController gives this nearly for free, or a simple @AppStorage list of the last 10 URLs.
5. **Reopen last document on launch.** Pairs with #4. Most viewers do this and it saves a trip to the Open dialog.
6. **Page rotation.** Rotate Left / Rotate Right buttons for the current page (PDFKit `page.rotation += 90`), with save. Useful for scanned docs that come in sideways.
7. **Export page as image.** Right-click a thumbnail, "Export as PNG". You already render pages as images for the sidebar, so most of the code exists.
8. **Annotations: highlight and sticky notes.** PDFKit has built-in annotation support (PDFAnnotation). This is the biggest functional gap versus Preview. Medium effort, high value if you mark up documents.
9. **OCR for scanned PDFs.** You already have OCR experiments in the repo (test_ocr.py, ocr_comparison). Apple's Vision framework (VNRecognizeTextRequest) can add a searchable text layer natively in Swift with no Python dependency. Would make Cmd+F work on scans like this FedEx label.

## UI

10. **QUICK WIN: Thumbnail size slider** at the bottom of the sidebar (small / medium / large). Now that thumbnails render sharp at any width, letting you shrink them means more pages visible at once.
11. **Arrow-key navigation in the sidebar.** Up/Down moves the selected page when the sidebar has focus. Currently mouse only.
12. **Page number jump field.** A small "Page __ of N" box in the toolbar where you can type a page number and hit Return. Faster than scrolling on long documents.
13. **Two-page (facing) view mode** in the view mode picker. PDFKit supports `.twoUp` display mode directly, so this is a small change.

## My recommendation for the next session

Do #4 + #5 (recent files / reopen last) and #10 (thumbnail slider) together as a v6.4.0. They are all small, low risk, and things you'd feel every day. #8 (annotations) is the best candidate for the next big feature after that.
