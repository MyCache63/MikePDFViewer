# Opening a document with many windows open - v6.27.0 - 2026-10-04

## What the log showed

The app's timing log had 274 opens. Since 25 September, PDFs took a median of 1.6 seconds to
open and up to 5.8 seconds. Markdown took a median of 1.5 seconds. The same small wedding script
took 1.6 seconds in a new window and 0.3 seconds when its window already existed, so the file
itself was never the slow part.

## Where the time went

I split each PDF open into two timings: reading the file, and waiting for the app's main thread
to show it. Then I ran a hidden copy of the app, under a different name with its own settings and
log, and opened 32 of your client PDFs into it one after another. Nothing appeared on your screen.

| Windows open | Reading the file | Waiting for the main thread, before | After |
|---|---|---|---|
| 2 to 4 | 0 to 18 ms | 297 to 472 ms | 115 to 122 ms |
| 29 to 33 | 0 to 3 ms | 1,551 to 6,939 ms | 135 to 144 ms |

## The cause

Two things made every open window rebuild itself whenever any document opened.

1. Every window watched the shared Recent Files list, and every open adds to that list.
2. The app's menu code lived in the top-level app object, which reacts to every window switch and
   pushes the change down to every window.

So with 30 windows open, one open meant 30 full window rebuilds before the new document could be
drawn.

## The fix

Recent Files is now one shared list that windows read without watching it. Only the menu and the
small Recent Files list on an empty window watch it. The menus moved into their own piece, so a
window switch refreshes the menus and nothing else. I checked in the hidden copy that File, View,
Tools and Window still carry every item, including Open, Recent PDFs and Put Background Windows to
Sleep.

## Status

v6.27.0 is built, committed, pushed and installed. Quit with Cmd+Q and relaunch. The Speed tab in
Settings and the log now show each PDF open split into read time and waiting time, so we can see
if this ever creeps back.
