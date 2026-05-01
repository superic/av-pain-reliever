import Foundation

/// Errors thrown by `ProcessOBSController.switchScene`.
public enum OBSError: Error, Equatable {
    /// `Process.run()` itself failed (binary not executable, etc.).
    case launchFailed(String)
    /// `obs-cmd` exited non-zero. Carries exit code + captured output
    /// for the log line.
    case nonZeroExit(code: Int32, stdout: String, stderr: String)
}

/// Abstraction over the OBS scene-switch side effect so the engine can
/// be tested without spawning processes.
public protocol OBSController {
    func switchScene(_ name: String) throws
}

/// Production `OBSController` that shells out to the `obs-cmd` CLI —
/// the same dependency the Hammerspoon engine uses, kept for the same
/// reason: the OBS team-maintained CLI handles obs-websocket auth and
/// version-skew quirks for us, so we don't need a native WebSocket
/// client (locked architectural choice in `SWIFT_PORT.md`).
///
/// Synchronous: `switchScene` blocks until `obs-cmd` exits (~50 ms).
/// The engine debounces USB events into a single trailing-edge
/// evaluation, so a brief block per profile change is fine; if it ever
/// becomes a problem we wrap the call in a `DispatchQueue` hop at the
/// caller, not in here.
public struct ProcessOBSController: OBSController {
    public let executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    /// Convenience initializer that searches the standard install
    /// locations. Returns nil if `obs-cmd` isn't installed — the engine
    /// then logs a warning per scene-switch request and continues
    /// (matching the Hammerspoon behavior).
    public init?() {
        guard let path = Self.locateExecutable() else { return nil }
        self.executablePath = path
    }

    public func switchScene(_ name: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["scene", "switch", name]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw OBSError.launchFailed(String(describing: error))
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outStr = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errStr = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw OBSError.nonZeroExit(code: process.terminationStatus, stdout: outStr, stderr: errStr)
        }
    }

    /// Search the same locations the Hammerspoon engine searches:
    /// Homebrew on Apple Silicon, Homebrew on Intel, and `cargo install`
    /// in the user's home. Returns the first executable found, or nil.
    public static func locateExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/obs-cmd",
            "/usr/local/bin/obs-cmd",
            (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin/obs-cmd"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
