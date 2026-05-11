import Foundation

/// Suppresses watcher callbacks that echo a write the app itself
/// just performed. `AppDelegate.bootEngine()` calls `stamp(_:)` after
/// every load so the gate knows what mtime is "current". The watcher
/// callback then asks `shouldReload(currentMTime:)` with a fresh stat
/// of `profiles.toml`; if the file's mtime hasn't moved past the
/// stamp, the event is the load's own write and we skip the reload.
///
/// Without this gate, the wizard's force-apply flow (which sets
/// `pendingForceApplyName`, writes the file, and reloads
/// synchronously) could be undone by the watcher's 250 ms-later
/// callback re-running the resolver against a cleared
/// `pendingForceApplyName`.
struct ConfigReloadGate {
    private(set) var lastLoadedMTime: Date?

    /// True when a reload should happen. A fresh gate (no stamp yet)
    /// always reloads. A nil current mtime means the file vanished
    /// since the last load; reload anyway so the caller can react.
    /// Otherwise reload only when the current mtime is strictly
    /// newer than the last stamp (an equal mtime is the load's own
    /// write echoing back).
    func shouldReload(currentMTime: Date?) -> Bool {
        guard let stamped = lastLoadedMTime else { return true }
        guard let current = currentMTime else { return true }
        return current > stamped
    }

    mutating func stamp(_ mtime: Date?) {
        lastLoadedMTime = mtime
    }
}
