# Responsiveness review - v02 - 2026-09-18 13:15 PT
App version measured: v6.21.0 (v01 measured v6.20.0)

## Correction to v01, and it matters

**v01 said the app took about 1.3 seconds to show a window. That number was wrong.** It came
from a script that starts the app and then asks System Events to count its windows, and System
Events itself costs about 600 milliseconds to answer. The app was never that slow.

The app now times itself from the moment the kernel starts the process, which is the honest
measure. **Launch to first window is 640 to 750 milliseconds.** On the same launches, my old
script reported 1246 to 1484, so it was overstating by roughly 600 every time.

I am telling you this because it changes what the remaining work is worth. The 400 milliseconds
I could not account for in v01 was mostly the measuring tool. There is no large unexplained gap
left to chase.

## What shipped in v6.21.0

### Timing built into the app

Every launch and every document open is now timed from inside the app and written to the
diagnostic log, so the numbers survive a quit and can be compared between versions. There is a
new **Speed tab in Settings** (Cmd+,) that lists recent timings, marks anything over 400
milliseconds in orange, and has a Copy button. That is the answer to your question about
internal logging: yes, it was worth adding, and it immediately earned its keep by catching my
own bad measurement.

Real numbers from five consecutive launches this morning:

| Event | Result |
|---|---|
| Launch to first window | 642, 644, 656, 678, 819 ms |
| Reopening the last markdown file | 155, 157, 163, 166, 170 ms |
| WebKit prewarm, now after the window | 25, 27, 28, 28, 30 ms |

### Launch changes

The WebKit prewarm no longer runs before your window. It waits until six tenths of a second
after launch, which keeps the benefit of having the web engine ready and takes its cost off the
critical path. Measured cold in a benchmark it was 115 milliseconds; measured in place now that
it runs later, it is 25 to 30.

Reopening the last file now happens one turn of the run loop after the window appears, instead
of during the first screen update. The log shows the order clearly: the window at 644
milliseconds, the document finishing about 300 milliseconds later. Total time to a readable
document is similar, but the window is on screen first.

Honest assessment of these two: they are small wins, not the 300 to 400 milliseconds I projected
in v01, because that projection rested on the inflated baseline. My launch script cannot resolve
a difference this size, so I am not going to claim one.

### Text viewer

This is the real win, and it is structural rather than a number I can quote back to you.

The plain text viewer used to count every line and rebuild the entire styled text inside the
view body, so both ran again on every screen update. On a 10 MB log that was 147 milliseconds
for the line count and 18 for the styled text, repeated constantly. Both now happen once, at
load and when you change the font, so typing in the search box on a large log no longer drags.

Reading the file also moved off the main thread, which is how every other viewer already worked.

## What is left

1. The biggest single number in the whole review is still **615 milliseconds to draw the first
   page of your 58 MB AMD PDF**. That is PDFKit drawing a genuinely complex page. A rough pass
   followed by the sharp one would put something on screen sooner. It is the most work of
   anything here, so I would only do it if that file annoys you in practice.
2. The main view is about 2,400 lines and SwiftUI evaluates all of it before the first paint.
   With the measurement corrected, I no longer think there is a large win here, so I would leave
   it alone unless the Speed tab starts showing launches creeping up.
3. There is one Swift 6 warning left in the markdown path, from the August work. It is harmless
   today and will need fixing whenever we move to Swift 6.

## How to use the Speed tab

Open Settings with Cmd+, and pick Speed. Anything slow shows in orange. If something feels
sluggish, look there first and send me the Copy output, which saves me guessing. The same lines
are in the log file, reachable from the Reveal Log button.
