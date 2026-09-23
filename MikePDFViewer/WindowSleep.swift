import SwiftUI
import AppKit

extension Notification.Name {
    /// Window > Put Background Windows to Sleep, and the button on the
    /// too-many-windows banner. Every window except the key one sleeps.
    static let sleepBackgroundWindows = Notification.Name("sleepBackgroundWindows")
}

/// Watches whether this window is the one in front, and runs a once-a-minute
/// check so a window left in the background can release its document.
/// A modifier of its own because the main view's chain has no type-checker
/// headroom left.
struct WindowLifecycleListener: ViewModifier {
    let activeState: ControlActiveState
    let onBecameKey: () -> Void
    let onLeftKey: () -> Void
    let onMinuteTick: () -> Void
    let onSleepRequest: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: activeState) { _, newState in
                if newState == .key { onBecameKey() } else { onLeftKey() }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if Task.isCancelled { break }
                    onMinuteTick()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepBackgroundWindows)) { _ in
                onSleepRequest()
            }
    }
}

/// Shown in place of the document while a window is asleep. It only stays on
/// screen for a moment in practice, because bringing the window forward wakes it.
struct SleepingWindowView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(fileName)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Asleep to save memory. Click in this window to reopen it.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Banner for when too many windows are open.
struct TooManyWindowsBanner: View {
    let count: Int
    let onSleepOthers: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("You have \(count) windows open, and each one holds its document in memory.")
                .font(.callout)
            Spacer(minLength: 8)
            Button("Sleep the Others") { onSleepOthers() }
                .help("Release every window except this one. Each reopens when you click into it.")
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
