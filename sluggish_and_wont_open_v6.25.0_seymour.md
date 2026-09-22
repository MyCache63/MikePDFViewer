# Why the file would not open, and why it is sluggish - v6.25.0 - 2026-09-22

## Your three questions, answered from the log

The app has been timing and logging itself since v6.21.0, so this is measured, not guessed.

### 1. Why clicking the file opened the app but no document

You clicked `CoC_GoldFleet_SameCourse_Simulation_v01_2026-09-21.md` twice this morning, at 5:32
and 5:33. The log shows the file being added to Recent Files both times, and **no open ever
starting**. That matches exactly what you saw.

This is my bug, from v6.17.0. That release added "if the file is already open, bring that window
forward instead of loading it twice". The check asked whether the window's stored file path
matched, and it never asked whether a document was actually on screen. Your window still held
that path from yesterday, when you had the file open, while showing the empty state. So every
click was answered with "you already have it", and nothing happened. Clicking again could not
help, because the answer was the same.

Fixed in v6.25.0. The window now has to be genuinely showing something before a click is turned
away. If the path matches but the window is empty, it loads the file. A failed open also releases
the window's claim on the file, so a retry is never blocked.

### 2. Why it is sluggish

You have **40 windows open** and the app is using **773 MB**. That is about 19 MB per window, and
it never goes down, because every window holds its whole document, its page images and its
thumbnails for as long as it is open.

The cost shows up in how long an open takes. Those CVS architecture PDFs are only 371 KB each,
and they took 2.7, 2.9, 3.1 and 3.8 seconds to open this morning. A file that small should open
in well under a second. The work is not the file, it is the other 40 windows.

### 3. Are we using memory well when a PDF is open but not in use? No.

Nothing is released when you stop looking at a window. There is no difference between the window
you are reading and the 39 you are not. Three ways to fix that, and I would like your call on
which:

1. **Close windows you are done with.** No code needed, and it is the whole fix today. A "Close
   All Documents" menu item would make it one action instead of 40.
2. **Free the inactive ones.** When a window has been in the background for a few minutes, drop
   its rendered pages and thumbnails and rebuild them when you return to it. This is the real fix
   and it is a day's work, with a risk of flicker when you switch back.
3. **Warn at a threshold.** Say something at 15 windows, so this never creeps up on you again.

My recommendation is 1 now and 2 next, with 3 thrown in because it is ten minutes.

## Also fixed: every bookmark save has been failing

Separately, the log shows this on every single file you have opened, for days:

```
Recents: bookmark FAILED ... Code=256 "Failed to retrieve app-scope key"
```

That is why Recent Files keeps losing permission and asking you to grant access again. The app
was signed ad-hoc, with no team identifier, and macOS will not issue the key a sandboxed app
needs to remember a file across launches without one.

v6.25.0 is signed with your Developer ID certificate instead, the one you already use for TASHA.
After you relaunch, those lines should read "bookmark saved". Recent Files will then survive a
quit, and the permission prompts should stop.

## What to do

Quit with Cmd+Q and relaunch. You will lose the 40 windows, which is also the point. If macOS
ever refuses to open it after a signing change, the fix is one command:
`xattr -dr com.apple.quarantine /Applications/MikePDFViewer.app`

Then tell me which of the three memory options you want.
