import Foundation
import SwiftUI
import Darwin

/// Timing record for launch and for every document open, so slow-downs show up
/// as numbers instead of impressions. Events go to the diagnostic log (they
/// survive a quit) and to a small in-memory list that Settings displays.
@MainActor
final class PerfLog: ObservableObject {

    static let shared = PerfLog()

    struct Event: Identifiable {
        let id = UUID()
        let name: String
        let milliseconds: Double
        let detail: String
        let at: Date

        var millisecondsText: String { String(format: "%.0f ms", milliseconds) }
    }

    @Published private(set) var events: [Event] = []

    private var launchLogged = false
    private let maxEvents = 200

    /// True process start, from the kernel, so launch timing includes the part
    /// before any of our code runs.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec)
                    + Double(started.tv_usec) / 1_000_000)
    }()

    // MARK: Recording

    func record(_ name: String, milliseconds: Double, detail: String = "") {
        let event = Event(name: name, milliseconds: milliseconds, detail: detail, at: Date())
        events.insert(event, at: 0)
        if events.count > maxEvents { events.removeLast(events.count - maxEvents) }
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        AppLog.write(String(format: "PERF %@ %.0f ms%@", name, milliseconds, suffix))
    }

    func record(_ name: String, since start: Date, detail: String = "") {
        record(name, milliseconds: Date().timeIntervalSince(start) * 1000, detail: detail)
    }

    /// Called when the app finishes launching, before the first window is up.
    func markLaunchFinished() {
        record("launch: app ready", since: PerfLog.processStart)
    }

    /// Called when the first window appears. Later windows are ignored, since
    /// only the first one measures launch.
    func markFirstWindow() {
        guard !launchLogged else { return }
        launchLogged = true
        record("launch: first window", since: PerfLog.processStart)
    }

    // MARK: Reading

    /// Plain text of the recent events, for the Copy button in Settings.
    func summaryText() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        return events.map { event in
            let detail = event.detail.isEmpty ? "" : "  \(event.detail)"
            return "\(stamp.string(from: event.at))  \(event.millisecondsText.padding(toLength: 9, withPad: " ", startingAt: 0))  \(event.name)\(detail)"
        }.joined(separator: "\n")
    }

    /// Average of every event with this name, for comparing across releases.
    func average(for name: String) -> Double? {
        let matching = events.filter { $0.name == name }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0) { $0 + $1.milliseconds } / Double(matching.count)
    }
}
