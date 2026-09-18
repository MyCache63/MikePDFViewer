# v6.23.1 PDF text selection - 2026-09-18 16:29 PT

Safety tag: `before-pdf-text-selection-2026-09-18`

## Problem
Michael could not select text in PDFs.

## Causes fixed
1. Find-bar and annotation-editing overlays used a full-height `Spacer` that intercepted mouse drags meant for the PDFView.
2. `PrintablePDFView.mouseDown` always ran annotation hit-testing first. It now checks `areaOfInterest(for:)` and passes text-area clicks straight to PDFKit unless the click is on a signature, sticky note, or free text.

## Also
- Markdown Reader: `user-select: text` on `body`.
- Verified: drag + Cmd+C on Kore_Citi_Fraud_DemoReview copied selected text.

## Note
Image-only scans have no text layer. Use Tools > Make Searchable first for those.
