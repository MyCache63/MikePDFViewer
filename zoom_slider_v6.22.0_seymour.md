# Zoom slider - v6.22.0 - 2026-09-18

There is now a zoom control floating in the bottom right of the document area. It has a minus
button, a slider, a plus button, a percentage readout, and a reset button.

**100 percent means the size the document opened at**, whatever the file is. That way the reset
button always brings you back to a sensible view, and the percentage means the same thing in
every viewer. Cmd+ and Cmd- move the slider too.

## Which files it works in, and what it actually does

| File | What the slider changes |
|---|---|
| PDF and email | The PDF page scale. Nothing happens until you use the slider, so a PDF still fits the window on its own until then. |
| Images | The scroll view magnification, the same zoom the toolbar buttons use. |
| SVG | The drawing scale in WebKit, so it stays sharp at any size. |
| HTML pages | Page zoom, the same as a browser. |
| Markdown, Reader view | Page zoom. |
| Text, log, JSON | The on-screen font size. Printing and export keep the size you chose in the font menu, so zooming never changes what comes out on paper. |
| CSV and TSV | The table font, the row height, and the column widths together. |

It is hidden for PowerPoint and Keynote, because the quick viewer has no zoom of its own, and for
the Quick markdown view, which is plain styled text.

## Tested

The SVG path is verified headlessly: at fit the drawing is 856 pixels wide, at 200 percent it is
exactly 1712, and the fit button restores 856 exactly. The rest is verified by the build and by
how each viewer's zoom already worked.

## Status

v6.22.0 is built, committed, pushed and installed. Quit with Cmd+Q and relaunch.
