import Foundation
import OSLog
import AVPainReliever

/// Production `ApplierLogger` that writes through Apple's unified
/// logging system. Visible in Console.app and via:
///
/// ```sh
/// log stream --predicate 'subsystem == "com.ericwillis.avpainreliever"'
/// ```
///
/// The Hammerspoon engine wrote a parallel file at
/// `~/.hammerspoon/logs/av-pain-reliever.log`; the Swift port replaces
/// that with `os.Logger`. Console.app's filtering and search make the
/// file appender redundant once we're on the unified system.
struct ConsoleLogger: ApplierLogger {
    private static let logger = Logger(
        subsystem: "com.ericwillis.avpainreliever",
        category: "engine"
    )

    func info(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
        Self.writeStderr("[info] \(message)")
    }

    func warn(_ message: String) {
        Self.logger.warning("\(message, privacy: .public)")
        Self.writeStderr("[warn] \(message)")
    }

    /// Mirror to stderr so `swift run` shows engine activity directly
    /// in the terminal. Especially useful for unbundled SPM builds,
    /// where `os.Logger` capture under the explicit subsystem isn't
    /// always reliable.
    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
