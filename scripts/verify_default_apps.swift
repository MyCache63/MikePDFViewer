// Prints the current macOS default app for every type MikePDFViewer opens.
// Run with:  swift scripts/verify_default_apps.swift
import Foundation
import CoreServices
import UniformTypeIdentifiers

let extensions = ["pdf", "md", "markdown", "txt", "log", "json", "svg", "eml", "html", "htm",
                  "csv", "tsv", "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp",
                  "docx", "pptx", "ppt", "key"]
for ext in extensions {
    guard let uti = UTType(filenameExtension: ext)?.identifier else { continue }
    let handler = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?
        .takeRetainedValue() as String? ?? "none"
    print("\(ext.padding(toLength: 9, withPad: " ", startingAt: 0)) -> \(handler)")
}
