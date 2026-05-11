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
/// Two kqueue sources cover the editor-save matrix:
/// - **Parent-directory source** with mask `[.write]` fires on
///   entry-list changes (create, delete, rename). Catches the
///   atomic-rename pattern used by `String.write(atomically: true)`,
///   TextEdit, and editors with `files.atomicSave`-style settings.
///   Also lets the watcher recover when the file is missing at
///   start, or is deleted and recreated out of band.
/// - **File source** with mask `[.write, .extend, .attrib, .delete,
///   .rename]` fires on content writes to the file inode. Catches
///   in-place writers like VS Code's default save on macOS, vim
///   without `backupcopy=no`, and `sed -i`.
///
/// The dir-source owns the file-source's lifecycle. After any
/// directory event it stat-compares the path's current inode to the
/// file fd's inode and rebinds when they differ. That removes the
/// source-firing-order race that would otherwise leave the file
/// source bound to an orphan inode after an atomic rename.
///
/// Both sources route through one debounce timer, so a save that
/// trips both (an atomic rename also fires the file fd's `.rename`)
/// coalesces into one `onChange` call. The debounce handler confirms
/// the target file still exists before firing, so sibling-only
/// directory writes are no-ops.
@MainActor
final class ProfileConfigWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private let debounceInterval: DispatchTimeInterval
    private var dirFD: Int32 = -1
    private var fileFD: Int32 = -1
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceTimer: DispatchSourceTimer?
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

    /// Open both watches and arm the kqueue sources. Safe to call
    /// repeatedly; re-arming closes the old sources first.
    func start() {
        stop()
        bindDir()
        bindFileIfPresent()
        Self.logger.debug("config-watcher: started (dirFD=\(dirFD), fileFD=\(fileFD))")
    }

    /// Tear down both watches. Idempotent.
    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        dirSource?.cancel()
        dirSource = nil
        fileSource?.cancel()
        fileSource = nil
        if dirFD >= 0 {
            close(dirFD)
            dirFD = -1
        }
        if fileFD >= 0 {
            close(fileFD)
            fileFD = -1
        }
        Self.logger.debug("config-watcher: stopped")
    }

    private func bindDir() {
        let dirPath = url.deletingLastPathComponent().path
        let opened = open(dirPath, O_EVTONLY)
        guard opened >= 0 else {
            Self.logger.info("config-watcher inactive: could not open dir \(dirPath) (errno=\(errno))")
            return
        }
        dirFD = opened
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            Self.logger.debug("config-watcher: dir event")
            self.scheduleReload()
            self.refreshFileBindingIfStale()
        }
        src.resume()
        dirSource = src
    }

    private func bindFileIfPresent() {
        let opened = open(url.path, O_EVTONLY)
        guard opened >= 0 else { return }
        fileFD = opened
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFD,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            Self.logger.debug("config-watcher: file event mask=\(src.data.rawValue)")
            self.scheduleReload()
            // Don't try to rebind from this handler. The dir-source
            // sees the same rename/delete as an entry-list change and
            // owns the rebind via `refreshFileBindingIfStale`.
        }
        src.resume()
        fileSource = src
    }

    /// Compare the path's current inode to the one our file fd holds.
    /// Atomic-rename replaces the path's inode without touching the fd,
    /// so a mismatch means the fd is bound to a now-orphan inode and
    /// the file-source must be rebound. Avoids the source-ordering
    /// race where the dir-source might run before the file-source's
    /// own `.rename` handler.
    private func refreshFileBindingIfStale() {
        let pathInode = inodeAtPath(url.path)
        let fdInode = inodeForFD(fileFD)
        guard pathInode != fdInode else { return }
        Self.logger.debug("config-watcher: file inode changed (\(fdInode as Any) → \(pathInode as Any)), rebinding")
        fileSource?.cancel()
        fileSource = nil
        if fileFD >= 0 {
            close(fileFD)
            fileFD = -1
        }
        bindFileIfPresent()
    }

    private func inodeAtPath(_ path: String) -> UInt64? {
        var s = stat()
        return stat(path, &s) == 0 ? UInt64(s.st_ino) : nil
    }

    private func inodeForFD(_ fd: Int32) -> UInt64? {
        guard fd >= 0 else { return nil }
        var s = stat()
        return fstat(fd, &s) == 0 ? UInt64(s.st_ino) : nil
    }

    private func scheduleReload() {
        Self.logger.debug("config-watcher: debounce armed")
        debounceTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + debounceInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceTimer = nil
            guard FileManager.default.fileExists(atPath: self.url.path) else {
                Self.logger.debug("config-watcher debounce fired but target missing; skip")
                return
            }
            // If a multi-step atomic save's dir event landed while
            // the target was transiently absent, the file source was
            // lost. The file exists now; rebind so the next in-place
            // edit isn't missed.
            if self.fileFD < 0 {
                self.bindFileIfPresent()
            }
            MainActor.assumeIsolated {
                self.onChange()
            }
        }
        t.resume()
        debounceTimer = t
    }

    deinit {
        // Best-effort fd close. Main-thread state mutations from stop()
        // aren't safe from deinit, so only the syscalls happen here.
        if dirFD >= 0 {
            close(dirFD)
        }
        if fileFD >= 0 {
            close(fileFD)
        }
    }
}
