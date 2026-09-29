// Makes MikePDFViewer the macOS default app for every file type it opens,
// except Word, PowerPoint and Keynote, which Michael edits in their own apps
// (the viewer can only preview them).
// Run with:  swift scripts/set_default_apps.swift
// The setting is per user, lives in the LaunchServices database, and survives
// app reinstalls.
//
// macOS 26.4 CHANGED THIS: each change now raises a "Use MikePDFViewer / Keep
// <old app>" dialog, one per type, and nothing changes until Michael clicks Use.
// The call still returns success straight away, so the verify script shows the
// old owner until he answers. Tell him before running this. Never click the
// dialogs by script: they are his consent to give.
//
// It prints the previous owner of each type so it can be undone:
//   duti -s <previous bundle id> <extension> all
import Foundation
import CoreServices
import UniformTypeIdentifiers

let bundleID = "com.mikeashe.MikePDFViewer"
let extensions = [
    "pdf", "md", "markdown", "txt", "log", "json", "svg",
    // NOT html or htm: on macOS 26, taking .html also makes the app the
    // default WEB BROWSER, so every web link opened in the viewer and failed
    // (29 Sep 2026). The viewer still opens .html via Open With or File > Open.
    "eml", "csv", "tsv",
    "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp",
]

var seen = Set<String>()
for ext in extensions {
    guard let type = UTType(filenameExtension: ext) else {
        print("\(ext): macOS has no type for this extension, skipped")
        continue
    }
    let uti = type.identifier
    guard seen.insert(uti).inserted else { continue }
    let before = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?
        .takeRetainedValue() as String? ?? "none"
    let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID as CFString)
    let result = status == noErr ? "set" : "FAILED (status \(status))"
    print("\(ext.padding(toLength: 9, withPad: " ", startingAt: 0)) \(uti.padding(toLength: 44, withPad: " ", startingAt: 0)) was \(before) -> \(result)")
}
print("\nCheck from a NEW process (this one can show cached values):")
print("  swift scripts/verify_default_apps.swift")
