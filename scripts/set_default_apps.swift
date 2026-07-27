// Registers MikePDFViewer as the macOS default app for .txt and .json.
// Run with:  swift scripts/set_default_apps.swift
// Needed once per Mac (survives app reinstalls; the setting is per-user
// in the LaunchServices database, keyed by bundle ID).
import CoreServices
import AppKit

let bundleID = "com.mikeashe.MikePDFViewer" as CFString
let types = ["public.plain-text", "public.json"]

for uti in types {
    let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID)
    print("\(uti): \(status == noErr ? "set" : "FAILED status \(status)")")
}
print("Verify in a NEW process (this one may show a cached value):")
print("  swift scripts/verify_default_apps.swift")
