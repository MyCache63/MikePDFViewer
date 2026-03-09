# MikePDFViewer Handover — March 9, 2026

## What We Built

### Native macOS App (v2)
A fast, native PDF viewer built in Swift/SwiftUI using Apple's PDFKit. Installed at `/Applications/MikePDFViewer.app` and set as the default PDF viewer on Michael's Mac.

**Features:**
- PDF viewing with continuous vertical scrolling
- Thumbnail sidebar for page navigation
- Search within PDF (Cmd+F) with highlighting
- Recent files menu (last 10 PDFs, persisted in UserDefaults)
- PDF Merge tool: drag-and-drop multiple PDFs, expand to see page thumbnails, click to include/exclude pages, reorder files, merge & save as new PDF
- Keyboard shortcuts: Cmd+O open, Cmd+F search, Shift+Cmd+M merge, Escape close
- Custom app icon (circular Q with red/white PDF magnifying glass design)

**Key Files:**
- `MikePDFViewer/MikePDFViewerApp.swift` — App entry point, scene/window setup, menu commands, onOpenURL handler
- `MikePDFViewer/ContentView.swift` — Main viewer with sidebar, search bar, toolbar, NSOpenPanel file picker
- `MikePDFViewer/PDFKitView.swift` — NSViewRepresentable wrapping PDFView, async document loading, search highlighting
- `MikePDFViewer/ThumbnailSidebar.swift` — LazyVStack of page thumbnails, async generation, scroll-to-current
- `MikePDFViewer/PDFMergeView.swift` — Full merge UI: drag-drop, page grid with include/exclude, reorder, NSSavePanel export
- `MikePDFViewer/RecentFilesManager.swift` — ObservableObject persisting recent file paths to UserDefaults
- `MikePDFViewer/Info.plist` — CFBundleDocumentTypes for com.adobe.pdf, CFBundleIconFile
- `MikePDFViewer/MikePDFViewer.entitlements` — App sandbox with read-write user-selected files
- `MikePDFViewer/AppIcon.icns` — macOS icon file generated from source PNG

### Web Version (aiquorum.org/pdf-viewer)
A fully client-side PDF viewer and merger that runs in the browser. No files are uploaded — everything processes locally using PDF.js and pdf-lib.

**Features:**
- Viewer tab: open/drop PDF, page rendering, thumbnail sidebar, zoom, search with prev/next
- Merge tab: add multiple PDFs, page thumbnails with click-to-exclude, reorder, download merged PDF
- Keyboard shortcuts: Cmd+O, Cmd+F, Escape
- Download banner linking to native Mac app on GitHub
- No login required (public page to drive traffic)

**Key Files (in AIQuorumPlatform repo):**
- `web/templates/pdf-viewer.html` — Self-contained HTML/CSS/JS page
- `web/static/pdf-viewer-icon.png` — App icon for the page header
- `app.py` — Route at `/pdf-viewer` (no auth required)

**Libraries used:** PDF.js 4.0.379 (Mozilla, via CDN), pdf-lib 1.17.1 (via CDN)

## Lessons Learned

1. **SwiftUI's `fileImporter` is very slow on first use** — takes 20-30 seconds. Replaced with `NSOpenPanel` which opens instantly. Use NSOpenPanel for macOS apps.

2. **App Sandbox entitlements matter** — started with `files.user-selected.read-only` which crashed on NSSavePanel. Changed to `files.user-selected.read-write` to allow saving merged PDFs.

3. **macOS Gatekeeper blocks unsigned apps** — `xattr -cr /Applications/MikePDFViewer.app` removes quarantine. Only needed once after install.

4. **Setting default PDF app from command line** — installed `duti` via Homebrew, then `duti -s com.mikeashe.MikePDFViewer com.adobe.pdf all`.

5. **App icons on macOS** — Asset catalog icons didn't show up reliably. Switched to generating a proper `.icns` file with `iconutil` and referencing it via `CFBundleIconFile` in Info.plist. Need to `killall Finder && killall Dock` and re-register with `lsregister` to flush icon cache.

6. **Async PDF loading** — loading PDFDocument on the main thread blocks the UI. Moved to `DispatchQueue.global(qos: .userInitiated)` with main-thread callback.

## Git Tags
- `good-basic-pdf-viewer-mar5` — v1, confirmed working
- `before-v2-features-mar5` — safety checkpoint before v2 work

## Repos
- **macOS app:** https://github.com/MyCache63/MikePDFViewer
- **Web version:** https://github.com/MyCache63/AIQuorumPlatform (route in app.py, template in web/templates/)

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

## What's Next (if continuing)
- GitHub Release with downloadable .zip/.dmg for the native app
- Add the PDF viewer link to the AIQuorum home page nav
- Deploy AIQuorum to make the web version live
- Possible features: annotations, bookmarks, dark mode PDF rendering, print support
