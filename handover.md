# MikePDFViewer Handover — March 11, 2026

## Current State: v5.6 — Fully Tested, All Features Working

**BUILD STATUS:** v5.6 builds, installed to `/Applications/MikePDFViewer.app`
**Version tag:** `v5.6` on GitHub
**Repo:** https://github.com/MyCache63/MikePDFViewer

### User-Confirmed Working (v5.5+)
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
