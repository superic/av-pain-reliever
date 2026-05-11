import Testing
import Foundation
@testable import AVPainReliever

/// Coverage for the bootstrap pipeline. Each test runs against a
/// fresh scratch directory AND injects a sibling-rename `quarantine`
/// closure so the production Trash op is never reached.
@Suite("ProfileBootstrapper")
struct ProfileBootstrapperTests {
    @Test("valid TOML loads to .loaded([profiles]) without touching the file")
    func validConfigLoads() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        let original = "[profiles.foo]\naudioInput = \"Mic\"\n"
        try original.write(to: url, atomically: true, encoding: .utf8)

        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: rejectQuarantine
        )

        guard case .loaded(let profiles) = outcome else {
            Issue.record("expected .loaded, got \(outcome)")
            return
        }
        #expect(profiles.count == 1)
        #expect(profiles.first?.name == "foo")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == original)
    }

    @Test("missing file triggers .bootstrapped([starter])")
    func missingConfigBootstraps() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")

        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: rejectQuarantine
        )

        guard case .bootstrapped(let profiles) = outcome else {
            Issue.record("expected .bootstrapped, got \(outcome)")
            return
        }
        #expect(profiles.count >= 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("malformed TOML moves the file aside and writes a fresh starter")
    func malformedQuarantines() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        let corrupt = "[profiles.foo\nbroken"
        try corrupt.write(to: url, atomically: true, encoding: .utf8)

        let quarantineDest = dir.appendingPathComponent("aside.toml")
        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: siblingRename(to: quarantineDest)
        )

        guard case .quarantinedAndReset(let profiles, let movedURL) = outcome else {
            Issue.record("expected .quarantinedAndReset, got \(outcome)")
            return
        }
        #expect(profiles.count >= 1)
        #expect(movedURL == quarantineDest)
        let movedContent = try String(contentsOf: movedURL, encoding: .utf8)
        #expect(movedContent == corrupt)
        let replaced = try String(contentsOf: url, encoding: .utf8)
        #expect(replaced != corrupt)
    }

    @Test("schema violation (wrong type) also moves the file aside")
    func schemaViolationQuarantines() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "[profiles.foo]\naudioInput = 42\n".write(to: url, atomically: true, encoding: .utf8)

        let quarantineDest = dir.appendingPathComponent("aside.toml")
        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: siblingRename(to: quarantineDest)
        )

        guard case .quarantinedAndReset(_, let movedURL) = outcome else {
            Issue.record("expected .quarantinedAndReset, got \(outcome)")
            return
        }
        #expect(movedURL == quarantineDest)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("LoadOutcome carries the resulting URL from the injected quarantine op")
    func quarantineUrlIsPropagated() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "[broken".write(to: url, atomically: true, encoding: .utf8)

        let fakeTrashURL = dir.appendingPathComponent("FakeTrash/profiles.toml")
        try FileManager.default.createDirectory(
            at: fakeTrashURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: siblingRename(to: fakeTrashURL)
        )

        guard case .quarantinedAndReset(_, let movedURL) = outcome else {
            Issue.record("expected .quarantinedAndReset, got \(outcome)")
            return
        }
        #expect(movedURL == fakeTrashURL)
    }

    @Test("unrecoverable when the quarantine op throws")
    func unrecoverableWhenQuarantineThrows() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        let corrupt = "[profiles.foo\n"
        try corrupt.write(to: url, atomically: true, encoding: .utf8)

        let outcome = ProfileBootstrapper().loadOrBootstrap(
            from: url,
            logger: SilentLogger(),
            quarantine: rejectQuarantine
        )

        if case .unrecoverable = outcome {
            // Corrupt file stays in place: the production code would
            // leave a sibling-rename failure visible to the user the
            // same way.
            let onDisk = try String(contentsOf: url, encoding: .utf8)
            #expect(onDisk == corrupt)
        } else {
            Issue.record("expected .unrecoverable, got \(outcome)")
        }
    }

    @Test("LoadOutcome.profiles returns [] for .unrecoverable and the inner array otherwise")
    func loadOutcomeProfilesAccessor() {
        let p: [Profile] = []
        #expect(LoadOutcome.loaded(p).profiles.isEmpty)
        #expect(LoadOutcome.bootstrapped(p).profiles.isEmpty)
        #expect(LoadOutcome.quarantinedAndReset(p, quarantinedAs: URL(fileURLWithPath: "/tmp/x")).profiles.isEmpty)
        #expect(LoadOutcome.unrecoverable.profiles.isEmpty)
    }

    private func makeScratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bootstrap-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Test seam: rename to a known destination instead of the real
    /// Trash. Returns the destination URL the bootstrapper expects.
    private func siblingRename(to dest: URL) -> QuarantineOp {
        { source in
            try FileManager.default.moveItem(at: source, to: dest)
            return dest
        }
    }

    /// Test seam: always throw, simulating a filesystem failure.
    /// Production behavior mirrors this when `trashItem` throws.
    private let rejectQuarantine: QuarantineOp = { _ in
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// Minimal ApplierLogger conformance for tests: drops every call.
/// Tests assert on filesystem state and `LoadOutcome` shape, not on
/// log lines, so a silent logger is sufficient.
private struct SilentLogger: ApplierLogger {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}
