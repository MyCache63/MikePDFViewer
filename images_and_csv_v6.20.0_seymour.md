# Image and CSV viewers - v6.20.0 - 2026-09-18

## Images

The app opens png, jpg, jpeg, gif, heic, heif, tiff, tif, bmp and webp. Animated GIFs play.

The view scrolls and zooms: there are toolbar buttons for zoom out, zoom in, fit to window and
actual size, and you can pinch to zoom or scroll to pan. A large screenshot shrinks to fit when
it opens, while a small image opens at its own size instead of being blown up. The sidebar shows
the pixel dimensions and the file size.

Printing works. Export gives you PDF or PNG.

**Export as Word is blocked for images, on purpose.** Apple's Word writer silently drops pictures.
I tested it two ways, with a plain image attachment and with a file wrapper, and neither put any
image data in the .docx. Instead of handing you an empty Word file, the app now says to use PDF or
PNG.

**Preview is still the default app for images.** That was my recommendation and it stands, because
Preview is wired into the screenshot and Photos flow. Say the word if you want it switched and I
will run the registration script.

## CSV and TSV

The app opens .csv and .tsv in a real table, with a row-number column and column widths estimated
from the contents. The table only builds the rows on screen, so a large export still opens
instantly.

The parser handles the parts that usually break: commas inside quoted fields, quoted fields that
contain line breaks, and doubled quotes used as an escape. Rows with missing trailing columns are
padded so everything lines up. It picks the delimiter itself, using tabs for .tsv and choosing
between comma and semicolon for .csv by looking at the first line.

A toolbar button toggles whether the first row is treated as column headings, and the file
re-parses when you change it.

Printing works, and Export gives PDF, PNG or Word. The PDF repeats the header row on every page.

**Excel stays the default for .csv.** A double-click usually means you want to edit.

## What I tested headlessly

Fourteen checks, thirteen passed and one found the Word limitation above:

- Comma inside a quoted field survives, and so does a line break inside quotes.
- A doubled quote becomes one quote.
- A short row is padded to the full column count.
- Semicolon-delimited files are detected.
- Turning the header toggle off keeps all four rows.
- The CSV PDF contains both a header name and a cell value.
- An image converts to a one-page PDF at its true size.

## Status

v6.20.0 is built, committed, pushed and installed. Quit with Cmd+Q and relaunch, then open a
screenshot and one of your HubSpot CSV exports.
