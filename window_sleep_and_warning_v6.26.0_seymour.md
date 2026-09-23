# Background windows sleep, and a warning at 15 - v6.26.0 - 2026-09-23

## First, you are still on the September 18 build

The copy of the app you have running started on 18 September and now has 49 windows. None of the
last three releases are active in it, including the fix for clicks that opened nothing and the
signing change for Recent Files. Quit with Cmd+Q and relaunch once to get all of it.

## Windows now go to sleep

When a window has been in the background for 5 minutes, it lets go of its document: the PDF,
its drawn pages, the web page for markdown or HTML, the image, or the table. The window stays
open with a moon icon and the file name. Click into it and it reloads the file, and a PDF goes
back to the page you were on.

A window stays awake if any of these is true:

- You can still see it, so a document on your second screen never goes blank while you read.
- It has unsaved changes, or you're partway through annotating.
- OCR, a Word conversion or a markdown render is running in it.
- It's showing a PDF made in memory, such as a converted Word file, which a reload couldn't
  rebuild exactly.
- It's in split view, or presenting.

Window > Put Background Windows to Sleep does it immediately for everything except the window
in front.

## What it saves, measured

I opened three of your files and drew their pages the way a window does. They took 132 MB.
Releasing them gave back 72 MB within two seconds. The other 60 MB is shared framework cache that
does not grow with each extra window, so the saving per window is the part that matters. With 49
windows that is most of the difference between the app crawling and not.

Markdown reopens at the top of the file, not where you had scrolled. PDFs keep their page.

## The warning

When a new window takes you to 15, a banner appears at the top of it with the count and a
"Sleep the Others" button. It shows once each time you cross the line, not in every window after.

## Settings

Settings (Cmd+,) > General has both numbers. Sleep can be set from 1 to 60 minutes, or 0 for
never. The warning can be set in steps of 5, or 0 for never.

## Not tested live

I couldn't try the sleep and wake in the real app without quitting your 49 windows. The build
passes, the kit builds, and the memory release is measured. The Speed tab will log each "window
slept" with the app's memory at that moment, so we'll see it working from the first day.
