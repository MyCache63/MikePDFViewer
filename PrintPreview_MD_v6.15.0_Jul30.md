# Markdown print preview - v6.15.0 - 2026-07-30

## What was wrong

Your long .md printed as "Page 1 of 1" with microscopic text. The markdown-to-PDF step
used WKWebView's createPDF, which outputs the entire document as ONE very tall page.
The macOS print dialog then shrank that single page onto one sheet, which is exactly the
skinny column you saw in the preview.

## What v6.15.0 does

Cmd+P (or the printer button) on a markdown file now opens a Print Layout sheet BEFORE
the system print dialog:

- Live preview, properly split into real letter-size pages, with a page count.
- Font size: 8 to 24 pt (default 12 for print; on-screen reading size is untouched).
- Margins: Narrow (0.3 in), Normal (0.5 in), Wide (1 in).
- Fit to a page limit: pick 1 to 20 pages; the app shrinks the text (never below 35%)
  until the document fits, and tells you the scale it used.
- Print... then hands the paginated PDF to the normal system dialog, which will now
  say "Page 1 of N" and preview correctly. Cancel backs out.

Your choices are remembered between prints.

## Under the hood

New PaginatedHTMLToPDF renders through WKWebView's print operation saved to a file,
which honors page breaks (technique: https://developer.apple.com/forums/thread/705138).
Plain text (.txt/.log/.json) printing already paginated correctly and is unchanged.

## Status

v6.15.0 built, committed, pushed, installed to /Applications/MikePDFViewer.app.
Quit (Cmd+Q) and relaunch, then Cmd+P your long .md to try it.
