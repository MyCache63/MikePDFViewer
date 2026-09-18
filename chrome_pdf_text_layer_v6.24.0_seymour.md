# Why that AMD PDF's text will not click, and the new repair - v6.24.0 - 2026-09-18

## The file, not the app

`AMD_AIScreening_VendorComparison_v05_2026-09-18.pdf` was produced by headless Chrome. Chrome
writes a text layer that does not line up with what you see, so the viewer has nothing to grab
where you are clicking. Our app reads it with PDFKit, which is the same engine Apple's Preview
uses, so Preview shows you the same behaviour.

Measured on page 1 of your file:

| Test | Result |
|---|---|
| Search for "recruiter", which is plainly on the page | 0 hits |
| Search for "candidate" | 0 hits |
| Clicking a word, sampled at 63 points | 24 points return nothing at all |
| Words that do return | Broken, for example "candidat", "ecurity", "doe" |
| Dragging across the page and copying | Works, but comes out as "A MD · I I NTERVIEW SCREEN I NG" |

The footer is the clearest sign of the damage. The words KORE.AI and PREPARED answer a click
anywhere in a tall band, because the text sits at coordinates that have nothing to do with where
it is drawn.

## What I added: Tools > Rebuild Text Layer (OCR)

It reads every page with the Mac's own text recognition and replaces the text layer with what is
actually on the page. Run it on the AMD file and these are the measured results:

| Test | Before | After |
|---|---|---|
| Search "recruiter" | 0 hits | 4 hits |
| Search "candidate" | 0 hits | 6 hits |
| Clickable sample points | 39 of 63 | 44 of 54 |
| A word under the cursor | "candidat", "ecurity" | "candidate", "security" |
| Copied text | "A MD · I I NTERVIEW SCREEN I NG" | "AMD • AI INTERVIEW SCREENING" |

It took 1.7 seconds for the two pages.

**The cost, which the app warns you about before it runs.** Each page becomes a 300 dpi image,
because the bad text lives inside the page's own drawing instructions and rasterising is the only
way to remove it. The file grew from 435 KB to 1.3 MB, and the pages stop being vector, so they
are slightly softer if you zoom a long way in. Your original file is untouched until you use
Save As. The result is good but not perfect: OCR occasionally runs words together, as in
"at80to90percent".

Use it when you need to copy from or search a PDF like this. Leave it alone otherwise.

## The durable fix is upstream

Whatever builds these decks prints them through headless Chrome. Two ways to avoid the problem at
the source, either of which is better than repairing afterwards:

1. Print the HTML through Safari or WebKit instead, which is what this app uses for its own PDF
   output. WebKit writes a text layer that extracts cleanly.
2. If Chrome has to stay, take the wide `letter-spacing` off the headings, the footer and the
   legend. That spacing is what makes Chrome scatter the characters.

## Also in this release

The general text-selection bug you hit earlier today was fixed separately in v6.23.1, which is
already installed. That was ours: overlays were swallowing mouse drags. This note is about the
part that is the file.
