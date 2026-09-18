# SVG viewer, and what else the app is missing - v6.19.0 - 2026-09-18

## SVG is in, and it is the default

You were right, there was no SVG viewer. Any .svg opened before this went down the "assume
it's a PDF" path and failed.

v6.19.0 renders SVG with WebKit, the same engine Safari uses, so the drawing stays sharp at
any zoom instead of going blocky. The toolbar gets four buttons in SVG mode: zoom out, zoom
in, fit to window, and actual size. Printing works, and Export gives you PDF or PNG of the
drawing.

MikePDFViewer is now the macOS default app for .svg, so double-clicking one in Finder opens
it here. I verified that with LaunchServices: public.svg-image now points at
com.mikeashe.MikePDFViewer, alongside plain text and JSON from earlier.

I also tested the export path headlessly. A sample SVG rendered to a one-page PDF with its
text intact.

## What the app still cannot open

Here is everything common that fails today, with my recommendation on each. The current
list is pdf, eml, docx, pptx, ppt, key, md, txt, log, json, html and now svg.

| Type | Effort | Add? | Default? | Why |
|---|---|---|---|---|
| Images: png, jpg, heic, gif, tiff, webp, bmp | Small | Yes | No | You take screenshots constantly and this is the biggest gap. macOS draws all of these for us. I would leave Preview as the default, because it is wired into the screenshot and Photos flow, and stealing that is more disruption than it is worth. |
| csv, tsv | Medium | Yes | Your call | Your HubSpot contact pulls write CSVs into the client folders. Excel takes ten seconds to open one and mangles leading zeros and dates on the way in. A read-only table that opens instantly is genuinely useful. I would not make it default at first, because a double-click usually means you want to edit it. |
| xlsx | Small | Yes | No | Same quick viewer we already use for PowerPoint, so it is a few lines. Excel should stay the default for anything you edit. |
| yaml, yml, xml, plist, toml, ini, conf, env | Tiny | Yes | Yes for yaml and xml | These are plain text, so it is one line in the dispatch table. Nothing else on the Mac owns them properly, so default makes sense. |
| pages, numbers | Tiny | Yes | No | Keynote already works through the quick viewer, and these are the same three lines. Pages and Numbers should keep the double-click. |
| rtf, rtfd | Tiny | Yes | No | The text engine reads RTF natively. TextEdit can keep the default. |
| Code: swift, py, js, ts, sh, css, sql | Tiny | Yes | No | Free to add to the text viewer. Never default, because Xcode and VS Code need to own these. Syntax colouring would be real work, so I would skip it unless you want it. |
| epub | High | No | No | Needs a real unpacker and a chapter reader. Apple Books does it well already. |
| msg (Outlook) | High | Only if you get them | No | Outlook's own binary format, and it needs a parser written from scratch. Your .eml path already covers mail you export from Gmail. |
| zip | Medium | No | No | Finder unzips with a double-click. |
| mp4, mov, mp3, m4a | Medium | No | No | QuickTime is better at this than we would be. |

## What I would do next, in order

1. Images, because it closes the largest everyday gap.
2. CSV as a fast read-only table.
3. The one-line text types (yaml, xml, plist, conf) plus xlsx, pages and numbers through the
   quick viewer. That group is about an hour together.

Say the word and I will do items 1 to 3 in one release.

## Status

v6.19.0 is built, committed, pushed and installed to /Applications. Quit with Cmd+Q and
relaunch, then double-click any .svg.
