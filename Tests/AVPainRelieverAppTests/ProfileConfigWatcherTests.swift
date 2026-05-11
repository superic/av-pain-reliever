import Testing
import Foundation
@testable import AVPainRelieverApp

/// Coverage for the file-system watcher that replaced the menu's
/// "Reload Config" button. The watcher debounces filesystem events,
/// fires its callback on the main actor, and re-binds across the
/// atomic-rename pattern that `String.write(to:atomically:)` and
/// most text editors use to save.
///
/// Tests use a short debounce (50 ms) to keep wall-clock time small;
/// production uses 250 ms. Wait windows are intentionally generous
/// (a few hundred ms) so a slow CI runner doesn't flake.
@MainActor
@Suite("ProfileConfigWatcher")
struct ProfileConfigWatcherTests {
    @Test("fires onChange after an atomic-rename write")
    func firesOnAtomicWrite() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-\(UUID()).toml")
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        // Let the watch bind before mutating the file.
        try await Task.sleep(for: .milliseconds(50))

        try "modified".write(to: url, atomically: true, encoding: .utf8)

        // Give the debounce + main-queue hop room to fire. The wait
        // is 8x the 50 ms debounce, so anything other than exactly
        // one fire means the debounce is misbehaving.
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.count == 1)
    }

    @Test("debounces a burst of rapid writes into substantially fewer callbacks")
    func debounceCoalescesBurstWrites() async throws {
        // A burst of saves within the debounce window should land as
        // a small number of onChange calls. Models a text editor's
        // multi-step save (vim swap-file dance, autosave bursts).
        // Each atomic rename also resets the source via the rebind
        // path, so the strictest claim we can make is "callbacks
        // strictly fewer than writes" — a broken debounce would
        // produce one fire per write, which is what this asserts
        // against. A properly working debounce produces one or two.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-burst-\(UUID()).toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(150)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        let writeCount = 5
        for i in 0..<writeCount {
            try "burst-\(i)".write(to: url, atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(20)) // well under the 150 ms debounce
        }

        // Wait long enough for the debounce timer to settle past the
        // last write.
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.count >= 1)
        #expect(recorder.count < writeCount)
    }

    @Test("stop prevents further callbacks even if the file changes")
    func stopHaltsCallbacks() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-stop-\(UUID()).toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        try await Task.sleep(for: .milliseconds(50))
        watcher.stop()

        try "after-stop".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.count == 0)
    }

    @Test("missing file at start leaves the watcher inactive without crashing")
    func missingFileIsTolerated() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-missing-\(UUID()).toml")
        // Do not create the file.
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        // Even after a write, the watcher hasn't bound to anything,
        // so the callback never fires. We're confirming "no crash"
        // more than anything else.
        try "now-exists".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(200))

        #expect(recorder.count == 0)
    }
}

/// Main-actor recorder counting how many times the watcher fired.
/// Using a class with @MainActor isolation so the test assertions
/// run on the same actor as the watcher's callback, avoiding
/// data-race warnings and unsynchronized reads.
@MainActor
private final class FireRecorder {
    private(set) var count = 0

    func bump() {
        count += 1
    }
}
