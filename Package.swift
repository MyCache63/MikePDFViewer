// swift-tools-version: 5.9
import PackageDescription

// MikePDFViewerKit — reusable rendering core used by the standalone
// MikePDFViewer.app and by host apps (Mission Control etc.) that want to
// embed read-only document viewing without re-implementing it.
//
// Source files live under MikePDFViewer/ alongside the app target's source
// (so the Xcode project doesn't have to relocate them). The package excludes
// the app-only files: ContentView, MikePDFViewerApp, annotations, signatures,
// OCR, redaction, watermarks, presentation mode, merge, etc. Those features
// stay in the app target.

let package = Package(
    name: "MikePDFViewerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MikePDFViewerKit", targets: ["MikePDFViewerKit"])
    ],
    targets: [
        .target(
            name: "MikePDFViewerKit",
            path: "MikePDFViewer",
            exclude: [
                // App-only entry / root view
                "MikePDFViewerApp.swift",
                "ContentView.swift",
                // App-only features (annotation, signature, OCR, redaction, etc.)
                "AnnotationToolbar.swift",
                "AttachmentsSidebar.swift",
                "BookmarkManager.swift",
                "DOCXExporter.swift",
                "ExportImagesView.swift",
                "OCRService.swift",
                "OCRView.swift",
                "OpenWithMenu.swift",
                "PDFCompareService.swift",
                "PDFCompareView.swift",
                "PDFKitView.swift",
                "PDFMergeView.swift",
                "PageExtractView.swift",
                "PasswordSheet.swift",
                "PresentationView.swift",
                "RecentFilesManager.swift",
                "RedactionService.swift",
                "SignatureManager.swift",
                "SignatureView.swift",
                "ThumbnailSidebar.swift",
                "WatermarkService.swift",
                "WatermarkSheet.swift",
                // App-only UI plumbing
                "MarkdownReaderSettings.swift",
                "MarkdownTOCSidebar.swift",
                // App resources (handled by Xcode app target, not SwiftPM)
                "Assets.xcassets",
                "AppIcon.icns",
                "Info.plist",
                "MikePDFViewer.entitlements"
            ]
        )
    ]
)
