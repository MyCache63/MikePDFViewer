# Export menu (PDF / Word / PNG) - v6.18.0 - 2026-09-12

## What you asked for

You wanted a quick way to export the open document as PDF, Word or PNG, with an icon near
Share and a File > Export menu item.

## What shipped

Both entry points exist now and do the same thing:

- The toolbar has a new Export icon (a square with an arrow, right after Share). It's a
  menu with three items.
- File > Export has the same three items: Export as PDF, Export as Word (.docx), Export
  as PNG.

Each one opens a save panel next to the source file with a sensible name filled in.

## What each format does, by viewer mode

| Open file | Export as PDF | Export as Word | Export as PNG |
|---|---|---|---|
| PDF (or a converted email) | Saves a copy | Extracts the text of every page into a .docx (scanned PDFs need Make Searchable first) | Page images sheet (DPI, page range, PNG or JPEG) |
| Markdown | Real multi-page PDF, same look as the print preview | Styled text into .docx | Renders the PDF first, then the images sheet |
| Text / log / json | Multi-page PDF in your chosen monospace font | Plain text into .docx | Same as above |
| Word (.docx) quick view | Converts via the existing Word-to-PDF path | Copies the original file | Converts, then images sheet |
| PowerPoint / Keynote quick view | Not available yet; an alert says so | Same | Same |

The Word export uses Apple's built-in Office Open XML writer, so the .docx is a genuine
Word file. I tested that headlessly: the output is a real zip with word/document.xml and
the text inside it.

## Status

v6.18.0 built, committed, pushed, installed to /Applications. Quit (Cmd+Q) and relaunch.
Try it on a .docx: File > Export > Export as PDF should give you a PDF beside the original.
