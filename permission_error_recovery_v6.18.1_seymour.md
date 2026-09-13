# "You don't have permission to view it" on open - v6.18.1 - 2026-09-12

## What happened

The app is sandboxed. macOS only lets it read a file you have chosen yourself (open panel,
Finder double-click, drag), and that permission ends when the app quits. To reopen a file
from Recent Files or at launch, the app stores a "security-scoped bookmark" for it. Your
Therapist .md had no bookmark stored, so the reopen was refused with Cocoa error 257.

What I checked: your recents list has 10 files; 5 have bookmarks and 5 (all opened this
morning, including that one) do not. The old code discarded the bookmark error, so there is
no record of why those 5 failed. The two most recent files did get bookmarks, so it's
intermittent, and I don't yet know the trigger.

## What v6.18.1 does

1. Recovery instead of a dead end. When a file is refused for permission, you get a
   "Permission Needed" alert with a Grant Access button. It opens a panel already pointed at
   the file; click Open once and the app reads it and stores the bookmark, so it won't ask
   again for that file. This applies to PDF, Markdown and text opens.
2. Diagnostics. Every bookmark success or failure, and every failed open, is now written
   with the real error to a log file. Settings (Cmd+,) > General > Reveal Diagnostic Log
   shows it. Next time this happens, the log will say why.

## What to do now

Quit (Cmd+Q), relaunch, open the Therapist file from Recent Files, click Grant Access, then
Open. If it happens again on a different file, tell me and I'll read the log.

Log path: ~/Library/Containers/com.mikeashe.MikePDFViewer/Data/Documents/logs/mikepdfviewer.log
