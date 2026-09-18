# v6.23.0 performance picks - 2026-09-18 06:54 PT

Safety tag: `before-perf-picks-2026-09-18`

Implemented the four items Michael copied from `Performance_Candidates_v01_2026-09-18.html`.

## 1. Images off the main thread
`ImageViewerController.loadPayload(at:)` reads and decodes on a detached task. `ContentView.loadImageDocument` applies the payload on the main actor. Sandbox Cocoa 257 still surfaces for Grant Access.

## 2. EML read/parse off the main thread
`loadEMLDocument` uses `Task.detached` for `Data(contentsOf:)` + `EMLParser.parse`. `EMLToPDFConverter.convert` still hops to MainActor (WKWebView). UI assignment stays on MainActor.

## 3. Page-change isolation
New `@Observable DocumentPageState` holds `currentPage` / `totalPages`. Bound child views (`BoundPDFKitView`, `BoundThumbnailSidebar`, `PageStatusControl`, `BookmarkToolbarButton`) observe it. ContentView passes the object through without reading page fields in its own body, so PDF scroll no longer rebuilds the whole toolbar tree. `PDFKitView` also skips no-op page writes.

## 4. Thumbnail cache caps
`NSCache` now has `countLimit = 80` and `totalCostLimit = 40 MB`, with per-entry RGBA cost. Cache clears when the sidebar's document identity changes.
