import Foundation

/// Watches `profiles.toml` for out-of-band edits (hand edits in a
/// text editor, sync tools writing to the file, etc.) and invokes
/// `onChange` after a short debounce so the host can reload the
/// config without the user clicking anything.
///
/// Replaces the menu's "Reload Config" affordance. The wizard's save
/// path still drives an explicit reload synchronously; the watcher's
/// late callback is mtime-gated by the caller so app-originated
/// writes don't trigger a double-reload that would stomp on
/// force-apply state.
///
/// Implementation notes:
/// - kqueue via `DispatchSource.makeFileSystemObjectSource` on the
///   open file descriptor. Events run on the main queue so the
///   caller's `onChange` is safe to mutate UI state.
/// - On `.delete` or `.rename` (atomic-replace pattern used by
///   `ProfileWriter` and most text editors), the watcher cancels
///   the source, closes the old fd, then re-opens the path so we
///   re-bind to the new inode.
/// - 250 ms debounce coalesces editor-side multi-write saves (vim
///   et al.) into one callback.
/// - If the file is missing at start, the watcher logs and stays
///   inactive. The bootstrapper creates the file on first launch,
///   so in practice the file always exists by the time the watcher
///   starts.
final class ProfileConfigWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private let debounceInterval: DispatchTimeInterval
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceTimer: DispatchSourceTimer?
    private var shouldWatch = false
    private static let logger = ConsoleLogger(category: "config-watcher")

    init(
        url: URL,
        debounceInterval: DispatchTimeInterval = .milliseconds(250),
        onChange: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    /// Open the file and arm the kqueue watch. Safe to call
    /// repeatedly; re-arming closes the old source first.
    func start() {
        stop()
        shouldWatch = true
        openAndWatch()
    }

    /// Tear down the watch. Idempotent. Once stopped, any in-flight
    /// rebind callback from a prior atomic-rename event will see
    /// `shouldWatch == false` and exit without re-opening.
    func stop() {
        shouldWatch = false
        debounceTimer?.cancel()
        debounceTimer = nil
        source?.cancel()
        source = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    private func openAndWatch() {
        guard shouldWatch else { return }
        let opened = open(url.path, O_EVTONLY)
        guard opened >= 0 else {
            Self.logger.info("config-watcher inactive: could not open \(url.path) (errno=\(errno))")
            return
        }
        fd = opened

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            Self.logger.debug("config-watcher event mask=\(mask.rawValue)")
            self.scheduleReload()
            if mask.contains(.delete) || mask.contains(.rename) {
                // Atomic replace: the inode we have open is now
                // detached from the path. Cancel + re-open after the
                // cancel handler runs.
                src.cancel()
            }
        }

        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
            // Re-bind to the new inode for atomic-replace flows. A
            // small delay lets the rename settle before the open.
            // `shouldWatch` lets a concurrent stop() short-circuit
            // the rebind cleanly.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                guard let self, self.shouldWatch else { return }
                self.openAndWatch()
            }
        }

        src.resume()
        source = src
    }

    private func scheduleReload() {
        debounceTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + debounceInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceTimer = nil
            MainActor.assumeIsolated {
                self.onChange()
            }
        }
        t.resume()
        debounceTimer = t
    }

    deinit {
        // Best-effort fd close. Main-thread state mutations from stop()
        // aren't safe from deinit, so only the syscall happens here.
        if fd >= 0 {
            close(fd)
        }
    }
}
