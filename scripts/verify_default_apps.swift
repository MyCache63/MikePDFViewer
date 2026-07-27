// Prints the current macOS default app for .txt and .json.
// Run with:  swift scripts/verify_default_apps.swift
import Foundation
import CoreServices

for uti in ["public.plain-text", "public.json"] {
    if let handler = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?.takeRetainedValue() {
        print("\(uti) -> \(handler)")
    } else {
        print("\(uti) -> none")
    }
}
