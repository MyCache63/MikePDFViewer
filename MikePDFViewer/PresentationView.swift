import SwiftUI
import PDFKit

// MARK: - Shared appearance settings

/// Letterbox / pillarbox fill shown around a page whose aspect ratio does not
/// match the screen (16:9 slides on a 16:10 display, portrait pages, etc).
/// Stored as a hex string because Color is not AppStorage-encodable.
enum PresentationAppearance {
    static let fillColorKey = "presentation-fill-color"
    static let defaultFillHex = "#000000"

    static var fillColor: NSColor {
        let hex = UserDefaults.standard.string(forKey: fillColorKey) ?? defaultFillHex
        return NSColor(hexString: hex) ?? .black
    }
}

extension NSColor {
    /// Accepts "#RRGGBB" or "RRGGBB".
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                  green: CGFloat((value >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(value & 0xFF) / 255.0,
                  alpha: 1.0)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Presentation state

/// Page state plus the Acrobat-compatible key handling for full-screen mode.
@MainActor
final class PresentationController: ObservableObject {
    let document: PDFDocument
    @Published var currentPage: Int
    @Published var showControls: Bool = true

    var onExit: () -> Void = {}
    private var hideControlsTask: Task<Void, Never>?

    init(document: PDFDocument, startPage: Int) {
        self.document = document
        self.currentPage = max(0, min(startPage, document.pageCount - 1))
    }

    var pageCount: Int { document.pageCount }

    func next() {
        guard currentPage + 1 < pageCount else { return }
        currentPage += 1
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func previous() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func first() { currentPage = 0 }
    func last() { currentPage = max(0, pageCount - 1) }

    /// Reveal the page counter / close button, then fade them out again.
    func flashControls() {
        showControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.showControls = false
        }
    }

    /// Key map matches Adobe Acrobat's Full Screen mode:
    /// next = Right/Down/Return/Page Down/Space, previous = Left/Up/
    /// Shift+Return/Page Up, exit = Esc or Cmd+L, Home/End = first/last.
    /// Returns true when the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "l" {
                onExit()
                return true
            }
            return false
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 124, 125, 121, 49:          // right, down, page down, space
            next()
        case 123, 126, 116:              // left, up, page up
            previous()
        case 36, 76:                     // return, keypad enter
            shift ? previous() : next()
        case 115:                        // home
            first()
        case 119:                        // end
            last()
        case 53:                         // escape
            onExit()
        default:
            return false
        }
        return true
    }
}

// MARK: - Full-screen window

/// Borderless full-screen window. A plain NSWindow with no title bar cannot
/// become key (so it would receive no key events); this override fixes that.
final class PresentationWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Cmd+L must exit even though menu-key handling normally wins.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "l",
           onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class PresentationWindowController: NSObject, NSWindowDelegate {
    static let shared = PresentationWindowController()

    private var window: PresentationWindow?
    private var controller: PresentationController?
    private var previousOptions: NSApplication.PresentationOptions = []
    private weak var returnToWindow: NSWindow?

    var isPresenting: Bool { window != nil }

    func present(document: PDFDocument, startPage: Int) {
        guard document.pageCount > 0 else { return }
        if isPresenting { exit() }

        let host = NSApp.keyWindow
        returnToWindow = host
        let screen = host?.screen ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let state = PresentationController(document: document, startPage: startPage)
        state.onExit = { [weak self] in self?.exit() }
        controller = state

        let win = PresentationWindow(contentRect: frame,
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
        win.isOpaque = true
        win.backgroundColor = PresentationAppearance.fillColor
        win.level = .mainMenu + 1
        win.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        win.contentView = NSHostingView(rootView: PresentationView(controller: state))
        win.delegate = self
        win.onKeyDown = { [weak state] event in
            state?.handleKey(event) ?? false
        }
        window = win

        previousOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.flashControls()
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func exit() {
        guard let win = window else { return }
        NSApp.presentationOptions = previousOptions
        win.delegate = nil
        win.orderOut(nil)
        window = nil
        controller = nil
        NSCursor.unhide()
        returnToWindow?.makeKeyAndOrderFront(nil)
    }

    /// Never trap the user behind an always-on-top window: drop the level when
    /// they switch away (Cmd+Tab, another display), restore it when they return.
    func windowDidResignKey(_ notification: Notification) {
        window?.level = .normal
        NSApp.presentationOptions = previousOptions
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .mainMenu + 1
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }
}

// MARK: - Presentation content

struct PresentationView: View {
    @ObservedObject var controller: PresentationController
    @AppStorage(PresentationAppearance.fillColorKey)
    private var fillHex: String = PresentationAppearance.defaultFillHex

    private var fillColor: Color {
        Color(nsColor: NSColor(hexString: fillHex) ?? .black)
    }

    var body: some View {
        ZStack {
            fillColor.ignoresSafeArea()

            PresentationPDFView(controller: controller, fillColor: fillColor)
                .ignoresSafeArea()

            // Click anywhere to advance, Shift+click to go back (Acrobat behavior).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        controller.previous()
                    } else {
                        controller.next()
                    }
                }

            overlayControls
        }
        .onContinuousHover { phase in
            if case .active = phase { controller.flashControls() }
        }
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    controller.onExit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Exit Full Screen (Esc)")
                .padding()
            }
            Spacer()
            HStack {
                Spacer()
                Text("\(controller.currentPage + 1) / \(controller.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.55))
                    .cornerRadius(6)
                    .padding()
            }
        }
        .opacity(controller.showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: controller.showControls)
    }
}

struct PresentationPDFView: NSViewRepresentable {
    @ObservedObject var controller: PresentationController
    let fillColor: Color

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = controller.document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = NSColor(fillColor)
        if let page = controller.document.page(at: controller.currentPage) {
            pdfView.go(to: page)
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.backgroundColor = NSColor(fillColor)
        if let page = controller.document.page(at: controller.currentPage),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
    }
}
