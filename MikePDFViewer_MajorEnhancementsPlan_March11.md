# MikePDFViewer Major Enhancements Plan — March 11, 2026

## Overview
Adding 20 features to transform MikePDFViewer from a basic viewer into a full-featured PDF reader/editor. Organized into 8 implementation phases, ordered by dependencies and shared infrastructure.

---

## Shared Infrastructure (Built as Needed)

These foundations serve multiple features and must be built before the features that depend on them:

| Infrastructure | Serves Features | Built In |
|---|---|---|
| **Annotation Toolbar + AnnotatablePDFView** | Highlights, text annotations, signatures, redaction | Phase 2 |
| **PageRenderer utility** (extract from OCRService) | Redaction, watermark, compare, image export | Phase 5 |
| **Multi-document architecture** (tab support) | Tabs, split view, compare PDFs | Phase 4 |
| **BookmarkManager** (persistent storage) | Bookmarks (pattern reusable for signatures, prefs) | Phase 3 |
| **Thumbnail invalidation system** | Rotation, reorder, redaction, watermark | Phase 1 |

---

## Phase 1: Low-Hanging Fruit (No New Infrastructure)

### Feature 9: Copy Selected Text
- **Difficulty:** Trivial
- **Fix:** The KeyCatcherView steals focus from PDFView, preventing native text selection and Cmd+C. Replace KeyCatcherView with `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in the PDFKitView Coordinator. PDFView natively supports text selection and copy.
- **Changes:** PDFKitView.swift (event monitor), ContentView.swift (remove KeyCatcherView background, add Copy toolbar button)
- **Shortcut:** Cmd+C (native)

### Feature 10: Share Sheet
- **Difficulty:** Easy
- **API:** SwiftUI `ShareLink(item: url)` (macOS 13+)
- **Changes:** ContentView.swift (add ShareLink in toolbar)

### Feature 20: Display Modes (continuous/single/two-up)
- **Difficulty:** Easy
- **API:** `PDFView.displayMode` — `.singlePage`, `.singlePageContinuous`, `.twoUp`, `.twoUpContinuous`
- **Changes:** ContentView.swift (state + picker), PDFKitView.swift (accept displayMode param), MikePDFViewerApp.swift (View menu items)

### Feature 4: Dark Mode Reading
- **Difficulty:** Easy-Medium
- **API:** `pdfView.wantsLayer = true` + `pdfView.layer?.filters = [CIFilter(name: "CIColorInvert")!]`
- **Changes:** PDFKitView.swift (darkMode param, layer filter toggle), ContentView.swift (toggle button), MikePDFViewerApp.swift (View menu)
- **Risk:** CIColorInvert affects scrollbar/shadows too. Test carefully.

### Feature 5: Page Rotation
- **Difficulty:** Easy
- **API:** `PDFPage.rotation` (read-write Int, multiples of 90)
- **Changes:** PDFKitView.swift (notification handlers), ContentView.swift (rotate buttons), ThumbnailSidebar.swift (thumbnail invalidation via version counter)
- **New concept:** `documentVersion: Int` state that increments on mutations, forcing thumbnail regeneration

---

## Phase 2: Annotation Infrastructure + First Annotations

### Infrastructure: Annotation Toolbar + Custom PDFView
- **New file: AnnotationToolbar.swift** — SwiftUI toolbar with tool selection (highlight, underline, strikethrough, sticky note, free text)
- **New file: AnnotationState.swift** — ObservableObject with `currentTool`, `currentColor`, `isAnnotating`
- **Key change: PDFKitView.swift** — Replace plain `PDFView()` with custom `AnnotatablePDFView: PDFView` subclass that handles mouse events for annotation placement
- **Risk:** Must preserve all existing functionality (zoom, search, page tracking) when migrating to subclass. Do as separate commit.

### Feature 2: Highlight/Underline/Strikethrough
- **Difficulty:** Medium
- **API:** `PDFAnnotation(bounds:forType:withProperties:)` with types `.highlight`, `.underline`, `.strikethrough`
- **Flow:** User activates tool -> selects text -> `pdfView.currentSelection.selectionsByLine()` -> create annotation per line -> `page.addAnnotation()`
- **Changes:** PDFKitView.swift, AnnotationToolbar.swift, ContentView.swift

### Feature 1: Text Annotations (Sticky Notes + Free Text)
- **Difficulty:** Medium
- **API:** `.text` type for sticky notes (icon that expands), `.freeText` for text boxes
- **Flow:** User activates tool -> clicks on PDF -> popover for text entry -> create annotation at click point
- **Changes:** AnnotatablePDFView (mouseDown handler), ContentView.swift

### Feature 6: Form Filling
- **Difficulty:** Easy (PDFKit handles forms natively)
- **API:** PDFKit renders and handles form widgets automatically. Just detect forms and help navigate.
- **Changes:** ContentView.swift (form field detection, indicator), optional FormNavigator.swift
- **Note:** AcroForms work well. XFA forms and JavaScript validation not supported.

---

## Phase 3: Bookmarks and Page Manipulation

### Feature 3: Bookmarks/Favorites
- **Difficulty:** Medium
- **New file: BookmarkManager.swift** — ObservableObject, persists bookmarks keyed by file path to UserDefaults/JSON
- **New file: BookmarkSidebar.swift** — View showing bookmarked pages with labels, tap-to-jump
- **Model:** `struct Bookmark: Codable { id: UUID, pageIndex: Int, label: String, created: Date }`
- **Changes:** ContentView.swift (star toggle in toolbar, sidebar tab switching), ThumbnailSidebar.swift (bookmark indicator), MikePDFViewerApp.swift (Cmd+D menu)

### Feature 18: Page Reorder Within a PDF
- **Difficulty:** Medium
- **API:** `PDFDocument.exchangePage(at:withPageAt:)`, `.removePage(at:)`, `.insert(_:at:)`
- **Changes:** ThumbnailSidebar.swift (add drag-drop reorder with `.draggable()` + `.dropDestination()`), thumbnail cache invalidation
- **Risk:** Page index shifting after reorder. Thumbnail cache must fully invalidate.

### Feature 8: Page Extraction
- **Difficulty:** Easy (reuses merge pattern)
- **API:** Create new `PDFDocument()`, insert selected pages, write to file
- **New file: PageExtractView.swift** — UI similar to PDFMergeView but for current document
- **Alternative:** Multi-select in thumbnail sidebar + "Extract Selected" button

---

## Phase 4: Multi-Document Architecture

### Feature 11: Tab Support
- **Difficulty:** Hard (architectural change)
- **Approach:** Use macOS native window tabbing. Move `pdfURL` state from App struct into ContentView as `@State`. Each window/tab is independent. macOS Cmd+T creates new tabs automatically.
- **Changes:** MikePDFViewerApp.swift (remove shared pdfURL state, add handlesExternalEvents), ContentView.swift (change @Binding to @State)
- **Risk:** Structural change. Must preserve onOpenURL behavior. Do as separate commit.

### Feature 7: Split View
- **Difficulty:** Hard
- **New file: SplitPDFView.swift** — HSplitView with two independent PDFKitView instances
- **Changes:** ContentView.swift (split view toggle)
- **Depends on:** Multi-document architecture from Feature 11

### Feature 12: Presentation Mode
- **Difficulty:** Medium
- **New file: PresentationView.swift** — Fullscreen NSWindow with PDFView in singlePage mode, black background, arrow key navigation, Escape to exit
- **Changes:** ContentView.swift (Present button), MikePDFViewerApp.swift (menu command)

---

## Phase 5: Advanced Annotations

### Feature 13: Signature Tool
- **Difficulty:** Hard
- **New file: SignatureView.swift** — Drawing canvas (NSView tracking mouse events), Clear/Done/Import buttons
- **New file: SignatureManager.swift** — Save/load signatures from Application Support
- **API:** `PDFAnnotation` type `.stamp` for image-based signatures (cleaner than `.ink`)
- **Depends on:** Annotation toolbar from Phase 2

### Feature 14: Redaction
- **Difficulty:** Hard
- **New file: RedactionService.swift** — Flatten-and-replace logic
- **API:** Mark with black `.square` annotations -> flatten page to image at 300 DPI -> replace page with image-based page
- **Depends on:** Annotation toolbar, PageRenderer utility
- **Risk:** Flattening loses text selectability, increases file size. Must warn user. Mandatory confirmation dialog.

### Extract PageRenderer utility
- **New file: PageRenderer.swift** — Extract `renderPageToPNG` from OCRService.swift, generalize for JPEG support
- **Serves:** Redaction, watermark, compare, image export

---

## Phase 6: Security and Watermark

### Feature 15: Password Protection
- **Difficulty:** Medium
- **API (decrypt):** `PDFDocument.isLocked`, `PDFDocument.unlock(withPassword:)`
- **API (encrypt):** `PDFDocument.write(to:withOptions:)` with `.ownerPasswordOption`/`.userPasswordOption`
- **New file: PasswordSheet.swift** — Password entry for locked PDFs
- **New file: EncryptSheet.swift** — Set passwords for protection
- **Changes:** ContentView.swift (check isLocked on load), MikePDFViewerApp.swift (Protect PDF menu)

### Feature 16: Watermark
- **Difficulty:** Medium
- **New file: WatermarkService.swift** — Render page + watermark overlay via CGContext, replace page
- **New file: WatermarkSheet.swift** — Config UI (text, color, opacity, rotation, preview)
- **Approach:** For each page: get CGPDFPage, draw into new CGContext, draw rotated semi-transparent text on top, create new PDFPage from result

---

## Phase 7: Export to Images

### Feature 19: Export to Images
- **Difficulty:** Easy
- **New file: ExportImagesView.swift** — Format picker (PNG/JPEG), DPI selector, page range, output folder, progress bar
- **Reuses:** PageRenderer.swift from Phase 5
- **API:** `NSBitmapImageRep.representation(using: .jpeg/.png, properties:)`

---

## Phase 8: Compare PDFs

### Feature 17: Compare PDFs
- **Difficulty:** Very Hard (most complex feature)
- **New file: PDFCompareView.swift** — Side-by-side UI with difference overlay, synced page navigation, sensitivity slider
- **New file: PDFCompareService.swift** — Pixel-diff engine using Accelerate framework
- **Approach:** Render both pages at same DPI -> compare pixels -> generate red difference mask -> composite overlay
- **Depends on:** Multi-document (Phase 4), PageRenderer (Phase 5)
- **Risk:** Performance for large docs. Use 72-150 DPI for overview, higher on demand. Use `DispatchQueue.concurrentPerform` for parallel page comparison.

---

## New Files Summary

| File | Phase | Purpose |
|------|-------|---------|
| AnnotationToolbar.swift | 2 | Tool selection UI |
| AnnotationState.swift | 2 | Annotation mode state management |
| AnnotatablePDFView.swift | 2 | Custom PDFView with mouse handling |
| BookmarkManager.swift | 3 | Bookmark persistence |
| BookmarkSidebar.swift | 3 | Bookmark list UI |
| PageExtractView.swift | 3 | Page extraction UI |
| SplitPDFView.swift | 4 | Two-PDF side-by-side |
| PresentationView.swift | 4 | Fullscreen slideshow |
| SignatureView.swift | 5 | Signature drawing canvas |
| SignatureManager.swift | 5 | Saved signature storage |
| RedactionService.swift | 5 | Page flattening for redaction |
| PageRenderer.swift | 5 | Shared page-to-image rendering |
| PasswordSheet.swift | 6 | Password entry UI |
| EncryptSheet.swift | 6 | Password protection UI |
| WatermarkService.swift | 6 | Watermark rendering |
| WatermarkSheet.swift | 6 | Watermark config UI |
| ExportImagesView.swift | 7 | Image export UI |
| PDFCompareView.swift | 8 | Comparison UI |
| PDFCompareService.swift | 8 | Pixel-diff engine |

---

## Entitlements / Info.plist Changes

- **Info.plist:** Change `CFBundleTypeRole` from `Viewer` to `Editor` in Phase 2 (once annotations are supported)
- **Entitlements:** No new entitlements needed. Current sandbox + user-selected read-write + network client covers everything.
- **Application Support:** Sandbox already allows writing to app's own container for bookmarks, signatures, preferences.

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| KeyCatcherView stealing PDFView focus | Blocks text selection, copy, form filling, annotations | Replace with NSEvent local monitor in Phase 1 |
| Custom PDFView subclass migration | Could break zoom, search, page tracking | Separate commit, thorough testing |
| Thumbnail cache staleness | Stale thumbnails after rotation/reorder/redaction | Version counter invalidation system |
| Tab architecture change | Breaks onOpenURL, shared state | Separate commit, test file opening |
| Redaction security expectations | Users expect true redaction | Flatten-to-image approach + clear warning dialog |
| Compare performance | Slow for large documents | Low DPI overview, concurrent processing, Accelerate framework |

---

## Version Plan

- v3.0 (current): Save/Print/Zoom/GoToPage
- v3.1: Phase 1 (Copy, Share, Display Modes, Dark Mode, Rotation)
- v3.2: Phase 2 (Annotations: Highlight, Text, Forms)
- v3.3: Phase 3 (Bookmarks, Page Reorder, Extraction)
- v4.0: Phase 4 (Tabs, Split View, Presentation) — major architectural change
- v4.1: Phase 5 (Signatures, Redaction)
- v4.2: Phase 6 (Password, Watermark)
- v4.3: Phase 7 (Image Export)
- v5.0: Phase 8 (PDF Compare)
