# Notepad icon + tooltip fixes - v6.14.1 - 2026-07-28

## 1. Why the notepad icon was missing

Your screenshot's title bar reads v6.13.0, but the notepad shipped in v6.14.0. The app was
already running when the new build was installed, so the old copy stayed on screen.
Fix: quit MikePDFViewer completely (Cmd+Q) and relaunch. The yellow lined notepad icon
appears in the toolbar next to Share.

## 2. Tooltips on hover (v6.14.1)

Almost every icon already had a tooltip, but SwiftUI never shows `.help()` tooltips on a
DISABLED button. With an .md open, all the PDF-only icons (zoom, rotate, markup, etc.) are
disabled, so hovering them showed nothing.

v6.14.1 switches every toolbar icon in the main window to an AppKit-backed `.tooltip()`
(an `NSView.toolTip` attached as a background), which shows whether the icon is enabled
or not. Also added missing tooltips: search-bar clear button, EML attachment Save/Open
buttons, Notepad delete button.

Workaround source: https://blog.rampatra.com/adding-tooltips-to-swiftui-views-on-macos

## Status

- v6.14.1 built, committed, pushed, installed to /Applications/MikePDFViewer.app.
- After quit + relaunch you should see v6.14.1 under the window title.
- Tooltips appear after macOS's usual ~1 second hover delay.
- Test: hover grayed-out icons with an .md open; each should name itself.
