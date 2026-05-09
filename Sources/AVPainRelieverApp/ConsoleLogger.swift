import Foundation
import OSLog
import AVPainReliever

/// Production `ApplierLogger` that writes through Apple's unified
/// logging system. Visible in Console.app and via:
///
/// ```sh
/// log stream --predicate 'subsystem CONTAINS "ericwillis.avpainreliever"' --info --style compact
/// ```
///
/// Each instance carries its own `os.Logger` category so different
/// engine adapters log under filterable categories ("engine",
/// "CMIOSinkWriter", "CameraCaptureSession", etc.). The category
/// also gets prefixed onto the stderr mirror so `swift run` output
/// stays readable when multiple subsystems log concurrently.
struct ConsoleLogger: ApplierLogger {
    private let logger: Logger
    private let category: String

    init(category: String = "engine") {
        self.logger = Logger(
            subsystem: "com.ericwillis.avpainreliever",
            category: category
        )
        self.category = category
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeStderr("[\(category)] [info] \(message)")
    }

    func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        writeStderr("[\(category)] [warn] \(message)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeStderr("[\(category)] [error] \(message)")
    }

    /// Mirror to stderr so `swift run` shows engine activity directly
    /// in the terminal. Especially useful for unbundled SPM builds,
    /// where `os.Logger` capture under the explicit subsystem isn't
    /// always reliable.
    private func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
