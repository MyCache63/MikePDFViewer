# MikePDFViewer Handover — March 11, 2026

## Current State: v5.0 — All 20 Features Implemented

**BUILD STATUS: Builds successfully, not yet device-tested**

## What We Built

### Native macOS App (v5.0)
A full-featured PDF viewer/editor built in Swift/SwiftUI using Apple's PDFKit.

**All Features (20 total across 8 phases):**

Phase 1 (v3.0-3.1): Foundation
- PDF viewing with continuous/single/two-up display modes
- Thumbnail sidebar, search (Cmd+F), recent files
- Save (Cmd+S), Save As (Shift+Cmd+S), Print (Cmd+P)
- Zoom In/Out/Fit, Dark Reading Mode, Page Rotation
- Copy selection, Share sheet, Go to Page (Cmd+G)
- OCR with DOCX export (Shift+Cmd+R)
- PDF Merge tool

Phase 2 (v3.2): Annotations
- Highlight, Underline, Strikethrough (select text, then apply)
- Sticky Notes and Free Text annotations
- Annotation toolbar with color picker
- Form field detection and native form filling

Phase 3 (v3.3): Page Management
- Bookmarks with sidebar section and toggle (Cmd+D)
- Page extraction to new PDF
- Page reorder via drag-and-drop in thumbnail sidebar

Phase 4 (v4.0): Multi-Document
- Tab support (each window independent, Cmd+N for new window)
- Split view (same document in two panes)
- Presentation mode (fullscreen, arrow keys, space bar)

Phase 5 (v4.1): Advanced Annotations
- Signature tool (draw, save, reuse signatures)
- Redaction (select text → flatten to image, with confirmation)
- PageRenderer shared utility

Phase 6 (v4.2): Security & Watermark
- Password protection (decrypt locked PDFs, encrypt with owner/user passwords)
- Watermark (configurable text, size, opacity, rotation, color)

Phase 7 (v4.3): Export
- Export pages as PNG or JPEG (72/150/300 DPI, page range selection)

Phase 8 (v5.0): Compare
- PDF comparison (side-by-side or difference overlay, sensitivity slider)

**Key Files (25 Swift files):**
- `MikePDFViewerApp.swift` — App entry, menus (File/Edit/View/Tools/Print)
- `ContentView.swift` — Main viewer, all toolbar buttons, sheet/alert orchestration
- `PDFKitView.swift` — NSViewRepresentable, notification handlers, SignatureAnnotation
- `ThumbnailSidebar.swift` — Thumbnails with bookmarks, drag-to-reorder
- `AnnotationToolbar.swift` — Highlight/underline/strikethrough/note/text tools
- `BookmarkManager.swift` — Persistent bookmarks per file
- `PageExtractView.swift` — Page selection grid and extract
- `PresentationView.swift` — Fullscreen slideshow mode
- `PageRenderer.swift` — Shared page-to-image rendering (PNG/JPEG)
- `SignatureView.swift` + `SignatureManager.swift` — Draw/save/apply signatures
- `RedactionService.swift` — Flatten-and-replace redaction
- `PasswordSheet.swift` — Unlock + Encrypt sheets
- `WatermarkService.swift` + `WatermarkSheet.swift` — Text watermark
- `ExportImagesView.swift` — Export pages as images
- `PDFCompareService.swift` + `PDFCompareView.swift` — Pixel-diff comparison
- `PDFMergeView.swift`, `RecentFilesManager.swift`, `OCRService.swift`, `OCRView.swift`, `DOCXExporter.swift`

## Architecture Notes

- **Cross-view communication**: FocusedSceneValue for read state (menu → focused window), NotificationCenter for actions
- **Tab support**: ContentView owns `@State var pdfURL` (not a binding from App). Each window is independent.
- **Thumbnail invalidation**: `documentVersion` counter increments on any mutation, triggers thumbnail regeneration
- **Type-checker workaround**: ContentView body split into `viewWithAlerts` → `viewWithNotifications` → body to avoid "unable to type-check" errors

## Git Tags
- `good-basic-pdf-viewer-mar5` — v1, confirmed working
- `before-v2-features-mar5` — safety checkpoint
- `before-save-print-features-mar11` — safety checkpoint before v3.0
- `before-phase3-build-mar11` — safety checkpoint before Phase 3 build

## Repos
- **macOS app:** https://github.com/MyCache63/MikePDFViewer
- **Web version:** https://github.com/MyCache63/AIQuorumPlatform

## Build & Install Commands
```bash
# Build release
xcodebuild -project MikePDFViewer.xcodeproj -scheme MikePDFViewer -configuration Release clean build

# Install to Applications
cp -R ~/Library/Developer/Xcode/DerivedData/MikePDFViewer-*/Build/Products/Release/MikePDFViewer.app /Applications/MikePDFViewer.app
xattr -cr /Applications/MikePDFViewer.app

# Re-register icon with Finder
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/MikePDFViewer.app
killall Finder; killall Dock

# Set as default PDF app
duti -s com.mikeashe.MikePDFViewer com.adobe.pdf all
```

## Known Considerations
- Redaction flattens pages to images (lossy, increases file size) — user is warned via confirmation dialog
- PDF Compare is pixel-based at 150 DPI — may be slow for very large pages
- Signature annotations use custom draw override — may not persist perfectly in all PDF readers
- Password encryption uses PDFKit's built-in options — standard PDF encryption
