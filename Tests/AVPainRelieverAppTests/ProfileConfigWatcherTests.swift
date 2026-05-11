import Testing
import Foundation
@testable import AVPainRelieverApp

/// Coverage for the file-system watcher that replaced the menu's
/// "Reload Config" button. See `ProfileConfigWatcher` for the design
/// rationale.
///
/// Each test gets its own scratch subdirectory so unrelated activity
/// in the system temp root (other processes, leftover test files)
/// can't trip the dir-watch and flake the assertions.
///
/// Tests use a short debounce (50 ms) to keep wall-clock time small;
/// production uses 250 ms. Wait windows are intentionally generous
/// (a few hundred ms) so a slow CI runner doesn't flake.
@MainActor
@Suite("ProfileConfigWatcher")
struct ProfileConfigWatcherTests {
    @Test("fires onChange after an atomic-rename write")
    func firesOnAtomicWrite() async throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "initial".write(to: url, atomically: true, encoding: .utf8)

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

    @Test("debounces a burst of rapid writes into a single callback")
    func debounceCoalescesBurstWrites() async throws {
        // Models a text editor's multi-step save (vim swap-file
        // dance, autosave bursts). All child writes fall inside the
        // same dir-level kqueue window and the debounce timer
        // collapses them to one fire.
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)

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

        #expect(recorder.count == 1)
    }

    @Test("stop prevents further callbacks even if the file changes")
    func stopHaltsCallbacks() async throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)

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

    @Test("missing file at start, then created → watcher picks it up")
    func missingFileThenCreated() async throws {
        // Parent dir exists, but the target file doesn't. The previous
        // file-fd watcher would stay inactive forever; the dir-fd
        // watcher picks up the create event.
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        try "first-write".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.count >= 1)
    }

    @Test("fires onChange after an in-place write (no rename)")
    func firesOnInPlaceWrite() async throws {
        // `atomically: false` writes to the existing inode in place.
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "initial".write(to: url, atomically: true, encoding: .utf8)

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        try "in-place-modified".write(to: url, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.count == 1)
    }

    @Test("in-place edit after atomic rename still fires onChange")
    func atomicRenameThenInPlaceWrite() async throws {
        // After an atomic write replaces the inode, a follow-up
        // in-place edit must still fire onChange.
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        try "atomic".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))
        let countAfterAtomic = recorder.count
        #expect(countAfterAtomic >= 1)

        try "in-place".write(to: url, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.count > countAfterAtomic)
    }

    @Test("atomic rename after in-place edit still fires onChange")
    func inPlaceWriteThenAtomicRename() async throws {
        // Symmetric to the atomic-then-in-place case. After an
        // in-place edit (which doesn't change the inode), a follow-up
        // atomic rename swaps the inode and the file source must
        // rebind cleanly to keep firing.
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        try "in-place".write(to: url, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))
        let countAfterInPlace = recorder.count
        #expect(countAfterInPlace >= 1)

        try "atomic".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.count > countAfterInPlace)
    }

    @Test("file deleted after start, then recreated → watcher picks it up")
    func deletedThenRecreated() async throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profiles.toml")
        try "seed".write(to: url, atomically: true, encoding: .utf8)

        let recorder = FireRecorder()
        let watcher = ProfileConfigWatcher(
            url: url,
            debounceInterval: .milliseconds(50)
        ) {
            recorder.bump()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(50))

        // Delete: the debounce may fire, but because the target is
        // missing the handler skips onChange. Record whatever happened
        // and verify the post-recreate count strictly exceeds it.
        try FileManager.default.removeItem(at: url)
        try await Task.sleep(for: .milliseconds(200))
        let countAfterDelete = recorder.count

        try "back-again".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.count > countAfterDelete)
    }

    private func makeScratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-watcher-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
