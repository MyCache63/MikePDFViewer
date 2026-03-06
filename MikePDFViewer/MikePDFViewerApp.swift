import SwiftUI

@main
struct MikePDFViewerApp: App {
    @State private var pdfURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(pdfURL: $pdfURL)
                .onOpenURL { url in
                    pdfURL = url
                }
        }
    }
}
