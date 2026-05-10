import Foundation
import OSLog
import AppKit

/// Exports recent unified-log entries from the main app process to
/// a plain-text file the user can attach to a bug report. Wired to
/// the menu's "Advanced > Save Logs for Support..." action.
///
/// Scope is the calling process only (`OSLogStore(scope:
/// .currentProcessIdentifier)`). The embedded Camera Extension runs
/// in a separate process, so its logs are NOT in this export. For
/// virtual-camera issues, ask the reporter to also capture Console.app
/// output filtered by `subsystem:com.ericwillis.avpainreliever.CameraExtension`.
///
/// Apple's unified log persists `.notice` and above by default;
/// `.debug` and `.info` entries are memory-only and never reach the
/// archive `OSLogStore` reads. `ConsoleLogger.info` maps to
/// `os.Logger.notice` for exactly this reason — our `info` lines
/// describe state transitions worth keeping, so they need to be
/// persisted. This export captures everything `ConsoleLogger`
/// promotes to `.notice` plus `.warning` / `.error` / `.fault`.
///
/// `.debug` calls (chatty per-event diagnostics) are intentionally
/// transient. For live debug-level diagnostics use
/// `log stream --level debug --predicate 'subsystem CONTAINS
/// "ericwillis.avpainreliever"' --style compact` directly.
enum LogExporter {
    /// User-facing entry point. Shows a save panel, dumps the last
    /// `windowMinutes` minutes of relevant log entries to the chosen
    /// file, and reveals it in Finder. Errors surface as an NSAlert.
    static func saveLogsWithPrompt(windowMinutes: Int = 60) {
        let panel = NSSavePanel()
        panel.title = "Save Logs for Support"
        panel.message = "Save the last \(windowMinutes) minutes of AV Pain Reliever log entries. Attach the resulting file when you contact support."
        panel.nameFieldStringValue = defaultFileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let count = try export(to: url, windowMinutes: windowMinutes)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            presentSuccess(count: count, url: url)
        } catch {
            presentFailure(error: error)
        }
    }

    /// Pull entries from `OSLogStore.local()` matching our subsystem
    /// prefix, format them, and write to `url`. Returns the count of
    /// entries written.
    static func export(to url: URL, windowMinutes: Int) throws -> Int {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: Date().addingTimeInterval(-Double(windowMinutes) * 60))
        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.ericwillis.avpainreliever")
        let entries = try store.getEntries(at: position, matching: predicate)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        var count = 0
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            let timestamp = formatter.string(from: log.date)
            let level = describe(level: log.level)
            lines.append("\(timestamp) [\(log.category)] [\(level)] \(log.composedMessage)")
            count += 1
        }

        let header = """
            # AV Pain Reliever support log
            # Generated: \(formatter.string(from: Date()))
            # Window: last \(windowMinutes) minute(s)
            # Process: main app only (Camera Extension logs are in a separate process; capture them via Console.app)
            # Subsystem prefix: com.ericwillis.avpainreliever
            # Entries: \(count)
            # Note: .debug entries are transient and never reach this export. For live debug capture, run:
            #   log stream --predicate 'subsystem CONTAINS "ericwillis.avpainreliever"' --level debug --style compact

            """
        let body = lines.joined(separator: "\n")
        let document = header + body + "\n"
        try document.write(to: url, atomically: true, encoding: .utf8)
        return count
    }

    /// `av-pain-reliever-log-2026-05-09T15-34.txt` — readable, sortable,
    /// safe for Finder.
    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm"
        return "av-pain-reliever-log-\(formatter.string(from: Date())).txt"
    }

    private static func describe(level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "undef"
        case .debug:     return "debug"
        case .info:      return "info"
        case .notice:    return "notice"
        case .error:     return "error"
        case .fault:     return "fault"
        @unknown default: return "?"
        }
    }

    private static func presentSuccess(count: Int, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Saved \(count) log entries"
        alert.informativeText = "Attach this file when you contact support:\n\(url.lastPathComponent)"
        alert.alertStyle = .informational
        alert.icon = AppIcon.image
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func presentFailure(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save logs"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.icon = AppIcon.image
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
