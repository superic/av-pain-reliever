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
    }

    func warn(_ message: String) {
        Self.logger.warning("\(message, privacy: .public)")
    }
}
