#!/bin/bash
# Captures everything Claude needs to diagnose the DOCX font scaling issue.
#
# Usage:
#   1. Open a .docx file in MikePDFViewer (v5.8.3 or later)
#   2. Wait for it to render in the viewer
#   3. Run this script: ./debug_docx_render.sh
#   4. Copy ALL the output and paste back to Claude

set -u

CONTAINER_TMP="$HOME/Library/Containers/com.mikeashe.MikePDFViewer/Data/Documents/MikePDFViewer/tmp"
RAW="$CONTAINER_TMP/debug-docx-raw.html"
SCALED="$CONTAINER_TMP/debug-docx-scaled.html"

echo "============================================================"
echo " MikePDFViewer DOCX Render Diagnostic"
echo " $(date)"
echo "============================================================"
echo ""

INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/MikePDFViewer.app/Contents/Info.plist 2>/dev/null || echo "???")
echo "Installed app version: $INSTALLED_VERSION"
echo "Looking in: $CONTAINER_TMP"
echo ""

if [ ! -f "$RAW" ] || [ ! -f "$SCALED" ]; then
    echo "ERROR: Diagnostic HTML files not found."
    echo ""
    echo "Steps:"
    echo "  1. Make sure /Applications/MikePDFViewer.app is v5.8.3 or later."
    echo "  2. Open any .docx file in MikePDFViewer."
    echo "  3. Wait for it to finish rendering."
    echo "  4. Re-run this script."
    echo ""
    echo "Folder contents (rendered PDFs from prior runs are normal):"
    ls -la "$CONTAINER_TMP" 2>/dev/null || echo "  (folder doesn't exist yet)"
    exit 1
fi

ls -la "$RAW" "$SCALED"
echo ""

echo "------------------------------------------------------------"
echo " Raw HTML <head>/<style> block (first 80 lines)"
echo "------------------------------------------------------------"
sed -n '/<head>/,/<\/head>/p' "$RAW" | head -80
echo ""

echo "------------------------------------------------------------"
echo " Scaled HTML <head>/<style> block (first 80 lines)"
echo "------------------------------------------------------------"
sed -n '/<head>/,/<\/head>/p' "$SCALED" | head -80
echo ""

echo "------------------------------------------------------------"
echo " Lines containing 'font' from RAW (first 30)"
echo "------------------------------------------------------------"
grep -n -i 'font' "$RAW" | head -30
echo ""

echo "------------------------------------------------------------"
echo " Lines containing 'font' from SCALED (first 30)"
echo "------------------------------------------------------------"
grep -n -i 'font' "$SCALED" | head -30
echo ""

echo "------------------------------------------------------------"
echo " Unified diff: raw -> scaled (the key signal)"
echo "------------------------------------------------------------"
DIFF_OUTPUT=$(diff -u "$RAW" "$SCALED")
if [ -z "$DIFF_OUTPUT" ]; then
    echo ">>> NO DIFFERENCES — the regex did NOT match anything in this file."
    echo "    Word's emitted HTML uses a font format the scaler is missing."
    echo "    Look at the 'font' lines above to see the actual format."
else
    echo "$DIFF_OUTPUT" | head -80
    echo ""
    echo ">>> Diff above. If 'font: NNpx' became 'font: MMpx' with M > N,"
    echo "    the scaler is working and rendering issue is elsewhere."
fi
echo ""

echo "------------------------------------------------------------"
echo " First 2000 bytes of RAW (in case head/style is elsewhere)"
echo "------------------------------------------------------------"
head -c 2000 "$RAW"
echo ""
echo ""
echo "============================================================"
echo " End of diagnostic. Copy ALL output above and paste to Claude."
echo "============================================================"
