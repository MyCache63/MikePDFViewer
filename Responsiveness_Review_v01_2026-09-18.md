# Responsiveness review - v01 - 2026-09-18 09:40 PT
App version measured: v6.20.0

## Headline

The app takes about **1.3 seconds** to put a window on screen. A bare SwiftUI app on this same
Mac takes about 0.5 seconds, so roughly 800 milliseconds is ours to work on. I can account for
about 400 of those and I want instrumentation before I guess at the rest.

Document loading is in good shape after the August work. **The one real problem left is the
plain text viewer**, which recounts every line and rebuilds the whole styled text on every
screen update. On a 10 MB log that is 165 milliseconds of work repeated for each update.

## How I measured

I compiled the app's own source files into small benchmark programs and timed each stage, the
same method as the August review. Launch times come from starting the app and polling until a
window exists, so treat those as accurate to about 100 milliseconds. The control is a minimal
SwiftUI app I built and launched the same way. Test files were your 58 MB AMD workshop PDF, a
300 page PDF I generated, a 10 MB text file, and a 50,000 row CSV.

## Launch

| Measurement | Result |
|---|---|
| MikePDFViewer to first window, three runs | 1254, 1470, 1359 ms |
| Same, with reopen-last-file turned off | 946, 1228, 1315 ms |
| Bare SwiftUI app, three runs (the floor) | 295, 635, 639 ms |
| WebKit prewarm on the main thread | 115 ms |
| Reading and resolving 10 recent-file bookmarks | 1.9 ms |
| Temp folder purge across 200 files | 0.8 ms |

### What I would change, in order

1. **Move the WebKit prewarm off the launch path.** It runs in `applicationDidFinishLaunching`
   and costs 115 ms on the main thread before your window can appear. Running it half a second
   after the window is up keeps every bit of its benefit, because you cannot open a markdown file
   in that half second anyway. This is a small, safe change.
2. **Show the window before loading the last file.** Reopening the last document is costing
   between 150 and 300 ms of the launch, because it happens during the first view update rather
   than after it. Deferring the load by one turn of the run loop means the window appears first
   and the document fills in behind it. The total time to a readable document stays the same, but
   the app stops looking frozen.
3. **Add launch timestamps to the diagnostic log.** About 400 ms sits between what I can account
   for and what I measured, and it is probably the size of the main view and the menu tree, both
   of which SwiftUI builds before the first paint. I do not want to restructure a 2,300 line view
   on a hunch. Four timestamps, at process start, at launch finish, at first view appearance and
   at first document shown, would tell us exactly where it goes. The log already exists, so this
   is a few lines.
4. **Then consider splitting the main view.** The toolbar alone is about 30 buttons, and the view
   carries roughly 25 modifiers for sheets, alerts and notifications. If item 3 points here, the
   fix is to break the toolbar into smaller pieces so SwiftUI has less to evaluate at once.

## Loading a document

| File | Stage | Result |
|---|---|---|
| 58 MB PDF, 1 page | Open the file | 39 ms |
| 58 MB PDF, 1 page | Render the first page | 615 ms |
| 300 page PDF | Open the file | 0.3 ms |
| 300 page PDF | Scan for form fields | 9.8 ms |
| 300 page PDF | Pre-warm 20 sidebar thumbnails (background) | 120 ms |
| 10 MB text | Read the file (main thread) | 7 ms |
| 10 MB text | **Count lines for the sidebar, per update** | **147 ms** |
| 10 MB text | **Rebuild the styled text, per update** | **18 ms** |
| 50,000 row CSV | Parse (background) | 176 ms |

### What I would change, in order

1. **Cache the text viewer's line count.** It is computed inside the view body, so every screen
   update counts all 120,000 lines again. On a 1 MB log that is about 16 ms per update, which is
   what makes typing in the search box feel sticky. Counting once at load and storing the number
   removes it entirely.
2. **Cache the styled text as well.** The same view rebuilds the whole attributed string on each
   update, which is another 18 ms on a large file. It only needs rebuilding when the file, the
   font or the size changes.
3. **Read text files on a background thread.** At 7 ms for 10 MB this is not urgent today, but
   every other viewer already does it, and a very large log would freeze the window.
4. **Render the first PDF page at lower resolution first.** Your 58 MB single-page PDF takes
   615 ms to draw because the page itself is complex. A quick rough pass followed by the sharp
   one would put something on screen sooner. This is the most work of the four and I would do it
   last.

## Things I expected to be slow that are not

I checked these before recommending anything, and none of them is worth touching:

- **Linking the heavy frameworks costs nothing.** I timed processes that link Vision, WebKit,
  PDFKit, QuickLook and CoreImage against one that links none. Every one started in 4 to 6 ms,
  because macOS keeps them in a shared cache. Making Vision load on demand would buy nothing.
- **The form-field scan is cheap.** It walks every page and every annotation before showing a
  PDF, which looked like a problem, but it costs 9.8 ms across 300 pages.
- **Recent-file bookmarks are cheap.** Resolving all ten takes 1.9 ms.
- **The temp folder purge is cheap**, at 0.8 ms across 200 files.
- **Thumbnail pre-warming already runs in the background** and never blocks the window.

## What this adds up to

Items 1 and 2 on the launch list should take 300 to 400 ms off the time before your window
appears, and they are both small changes. Items 1 and 2 on the document list end the stutter in
the text viewer. Item 3 on the launch list is what tells us whether the remaining 400 ms is worth
chasing.
