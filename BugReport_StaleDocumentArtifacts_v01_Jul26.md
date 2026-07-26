# Bug Report: Stale artifacts from the previous document - v01 - 2026-07-26

**Status:** FIXED in v6.12.5 (2026-07-26) - awaiting device test  
**App version at investigation:** v6.12.4  
**Fix version:** v6.12.5  
**Symptom:** Opening a document sometimes shows leftovers from the last one in the window title, left sidebar (thumbnails / outline-like chrome), and/or the main viewer. More common when several documents/windows are in play.

---

## Root causes (ranked)

### 1. PRIMARY (multi-window): Open is broadcast to EVERY window

**Where:**
- `MikePDFViewerApp.openPDF()` posts `.pdfOpenFile` with no target window
- Recent Files menu posts the same notification
- EML attachment open posts the same notification
- Every `ContentView` listens and does `pdfURL = url`:

```swift
// ContentView.swift ~309-313
.onReceive(NotificationCenter.default.publisher(for: .pdfOpenFile)) { notification in
    if let url = notification.userInfo?["url"] as? URL {
        recentFiles.add(url)
        pdfURL = url
    }
}
```

**What goes wrong:**  
`WindowGroup` creates one `ContentView` (and one full document state machine) per window. A single Open / Recent / attachment-open updates **all** windows. Titles flip everywhere; each window starts its own async load of the new file while still holding the previous `pdfDocument`. That matches your note about it getting worse with more docs open. The July 10 evaluation already flagged this as item 10 (notifications not scoped to the focused window).

Same pattern affects other global notifications (`.pdfDocumentModified`, zoom, rotate, find, display mode, dirty flag): an edit in one window can mark other windows dirty and bump their `documentVersion`.

---

### 2. PRIMARY (single window too): Thumbnail rows never reset on document change

**Where:** `ThumbnailSidebar.swift` - `ThumbnailItem` + `ForEach`

```swift
ForEach(0..<totalPages, id: \.self) { index in
    thumbnailRow(index: index)  // identity = page number only
}
```

Each row keeps `@State private var thumbnail: NSImage?` and `renderedPixelWidth`.

On a new document:
- `documentVersion` is reset to **0** for every open (`loadPDFDocument` etc.), so `onChange(of: documentVersion)` often **does not fire** (0 -> 0).
- There is **no** `.onChange` of the document identity and no `.id(document)` on the sidebar.
- `generateThumbnail` bails out if the pixel width did not increase:

```swift
guard pixelWidth > renderedPixelWidth else { return }
```

So SwiftUI reuses page-0, page-1, ... rows and keeps the **old bitmaps**. That is exactly "thumbnails from the last document."

**Bonus race:** background render completion always assigns `thumbnail = img` with no check that this row still belongs to the same `PDFDocument`, so a slow render from doc A can overwrite doc B's row after the switch.

The process-wide `thumbnailCache` keys by `ObjectIdentifier(document).hashValue` + page + version + width. Different `PDFDocument` instances usually get different keys, so the cache itself is secondary; the **@State reuse** is the real leak. (Hash collisions on `hashValue` are rare but the key should still use a stable document id, not `hashValue` alone.)

Sidebar multi-select (`selectedPages`) also survives a document switch for the same reason.

---

### 3. HIGH: Async loads have no "still the current open?" guard

**Where:** `ContentView.loadPDFDocument`, `loadEMLDocument`, `loadDOCXDocument`

```swift
DispatchQueue.global(...).async {
    let doc = PDFDocument(url: url)
    DispatchQueue.main.async {
        pdfDocument = doc   // always applied, even if user already opened something else
        ...
    }
}
```

**What goes wrong:**  
Open A (slow), then open B (fast). B paints correctly, then A's completion runs and **replaces** the viewer with A while `pdfURL` / title still say B (or the reverse depending on timing). Feels like "main view is the wrong document" or "title doesn't match what I see."

Nothing clears `pdfDocument` (or bookmarks, page index chrome) at the **start** of a load, so the previous document stays on screen for the whole load even without a race.

---

### 4. MEDIUM: Title vs content are updated on different schedules

**Where:**  
- Title: `.navigationTitle(pdfURL?.lastPathComponent ?? ...)` - updates as soon as `pdfURL` changes  
- Content: `pdfDocument` only after async load finishes  

So even a correct single-window open can briefly show **new title + old pages**. With bug 3, that mismatch can stick. With bug 1, every window's title jumps while content lags or races.

Bookmarks are reloaded only in the async success path for PDF/DOCX/EML, so the left column can also show the previous file's bookmark list until the new load finishes (and never cleared when switching to MD/TXT/HTML/Quick Look).

---

### 5. LOWER (related): Mode flags not fully cleared at load start

`loadDocument` clears text / Quick Look / HTML flags up front, but markdown / EML / DOCX flags and `pdfDocument` are cleared inside each loader's completion (or not at all if you bounce between modes quickly). Combined with async loaders, you can get short-lived mixed chrome (wrong sidebar branch vs main pane).

`PDFKitView.updateNSView` does correctly assign `pdfView.document` when the `PDFDocument` instance changes; the main canvas is not the primary single-window sticky bug once `pdfDocument` is right. Quick Look's `updateNSView` also swaps `previewItem` when the URL changes.

---

## How this maps to what you see

| Symptom | Likely cause |
|--------|----------------|
| Wrong thumbnails after open | #2 (state reuse + version always 0) |
| Wrong main page content | #3 (async race) and/or #1 (other window's load) |
| Wrong / mismatched title | #1 and/or #4 (url early, document late or raced) |
| Worse with more docs open | #1 (every window receives Open) |
| Left chrome / bookmarks from last file | #2 + bookmarks not cleared until load completes (#4) |

---

## Recommended fix plan (do not implement yet)

### A. Scope Open (and other commands) to the key window - highest impact for multi-doc

1. Stop using bare `NotificationCenter` for `.pdfOpenFile` as a fan-out to all `ContentView`s.
2. Preferred patterns (pick one):
   - Set `pdfURL` only on the focused scene (e.g. open panel / Recent handled via a small `ObservableObject` owned by the app, applied in the focused `ContentView` only), or
   - Post with `object: window` / scene id and filter in `onReceive`, or
   - Use SwiftUI `openWindow` / focused values so only the active window mutates.
3. While touching this, scope **all** menu-driven notifications the same way (open, zoom, rotate, find, modified, saved, display mode). The evaluation already called this out for v6.14.

### B. Force sidebar identity reset on every successful document bind

1. On `ThumbnailSidebar` (or the `NavigationSplitView` sidebar content):

   `.id(ObjectIdentifier(document))`  
   or `.id(pdfURL?.absoluteString ?? UUID().uuidString)`

2. In `ThumbnailItem`, also:
   - `onChange` of a stable document key (URL or ObjectIdentifier), clear `thumbnail` / `renderedPixelWidth` and regenerate
   - On async completion, ignore results if document identity no longer matches
   - Stop relying on `documentVersion` alone (it resets to 0 every open)

3. Clear `selectedPages` when the document identity changes.

4. Optional: `thumbnailCache.removeAllObjects()` on document close, or key by file URL + page + mtime/version, and set `totalCostLimit` (evaluation item 24).

### C. Make loads cancellable / generation-tagged

1. Add `@State private var loadGeneration = 0` (or store `loadingURL`).
2. At the start of every `loadDocument`:
   - increment generation
   - clear or nil-out `pdfDocument` (or show a loading placeholder)
   - clear mode flags, bookmarks, search text, current page in one shared `resetDocumentState()`
3. In every async completion: `guard generation == loadGeneration, url == pdfURL else { return }`.
4. Same guard for EML/DOCX/OCR replacement of `pdfDocument`.

### D. Small consistency cleanups

1. Single `resetViewerState(for: URL?)` used by all loaders so no mode flag is left behind.
2. `bookmarkManager.load(for:)` (or clear) at load **start**, not only success.
3. Keep title and content in sync: either don't change `navigationTitle` until load succeeds, or show a clear "Loading…" state when `pdfURL != loadedURL`.

---

## Suggested verification after a fix

1. Single window: open PDF A, then PDF B, then A again - title, thumbnails, and main view must all match B/A with no flashes of the other after load settles.
2. Two windows: Doc A in W1, Doc B in W2; Open C from menu - **only the key window** becomes C; the other keeps its document and title.
3. Rapid open: spam Open on several large PDFs; final window state must match the last chosen file only.
4. PDF -> MD -> PDF and PDF -> PPTX (Quick Look) -> PDF: no leftover thumbnails or bookmarks.
5. Annotate in W1 only: W2 must not become dirty.

---

## Files involved

| File | Role |
|------|------|
| `MikePDFViewer/ContentView.swift` | `loadDocument*`, `pdfURL` / `pdfDocument`, `.pdfOpenFile` receiver, title |
| `MikePDFViewer/MikePDFViewerApp.swift` | Open / Recent posts global `.pdfOpenFile` |
| `MikePDFViewer/ThumbnailSidebar.swift` | Stale `@State` thumbnails, cache, prewarm |
| `MikePDFViewer/PDFKitView.swift` | Main canvas swap (OK once document is correct); global notification handlers |
| `MikePDFViewer/BookmarkManager.swift` | Bookmarks only reloaded on load success |
| `MikePDFViewer/AttachmentsSidebar.swift` | Attachment open also broadcasts `.pdfOpenFile` |

---

## Recommendation summary

Fix **A + B + C** together. A alone stops multi-window cross-talk (your "number of docs open" clue). B alone stops sticky thumbnails in a single window. C alone stops wrong-document races in the main view and title/content skew. Doing only one will leave the other symptoms alive.
