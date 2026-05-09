import Foundation
import AVFoundation

/// Outcome of `CameraController.setPreferred(named:)`. Mirrors the
/// `AudioApplyResult` shape so `ProfileApplier` can map both into
/// engine log lines uniformly.
public enum CameraApplyResult: Equatable, Sendable {
    /// Camera found, `userPreferredCamera` set.
    case ok
    /// No camera with the given name in the discovery session.
    case notFound
}

/// One entry in the wizard's camera picker. AVFoundation's
/// `AVCaptureDevice.localizedName` is the user-facing identifier we
/// match against — the same string macOS shows in System Settings,
/// FaceTime, and the menu-bar Continuity Camera control.
public struct CameraSummary: Hashable, Sendable, Identifiable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public var id: String { name }
}

/// Engine-side write seam: sets the system's `userPreferredCamera`
/// by name. `ProfileApplier` consumes this; tests inject a recording
/// mock with no inventory ceremony.
public protocol CameraApplier {
    /// Set the system's `userPreferredCamera` to the camera with the
    /// given `localizedName`. Returns `.notFound` if no such camera
    /// is currently visible.
    func setPreferred(named: String) -> CameraApplyResult
}

/// Wizard-side read seam: enumerates available cameras and queries
/// the current preferred name. `AddProfileViewModel` consumes this;
/// tests inject a fake that returns canned snapshots.
public protocol CameraInventory {
    /// Snapshot of available cameras, sorted by name. Used by the
    /// wizard UI to populate the camera picker.
    func availableCameras() -> [CameraSummary]

    /// Localized name of the camera currently set as
    /// `userPreferredCamera`, or nil if none is set / matches.
    func currentPreferredName() -> String?
}

/// Abstraction over `AVCaptureDevice.userPreferredCamera` (macOS 14+
/// system-wide preferred camera). Composition of the apply + inventory
/// seams above. Production uses `AVFoundationCameraController`;
/// callers that legitimately need both (e.g., `AppDelegate`'s
/// dependency bundle) ask for the umbrella, and tests use a recording
/// mock per side.
///
/// Scope and design notes:
///
/// - `userPreferredCamera` is the macOS-14+ system API for
///   "preferred default camera." AVFoundation-modern apps (FaceTime,
///   browser `getUserMedia`, native AVCapture clients) pick it up
///   automatically.
/// - Apps with their own camera-selection UI (Zoom, Slack, Teams)
///   maintain their OWN selection independently. The engine
///   intentionally does NOT try to drive those: no plist hacks, no
///   UI scripting. For those, the V2 native virtual camera
///   (`VirtualCameraSourceController` below) is the bridge. The user
///   selects "AV Pain Reliever" once in each app's picker, and the
///   active profile drives which real camera the virtual camera
///   streams from.
public protocol CameraController: CameraApplier, CameraInventory {}

/// Drives the source camera that AV Pain Reliever's own virtual
/// camera streams from. Conceptually parallel to `CameraController`
/// (which sets the system-wide `userPreferredCamera`) but operates
/// on a different surface: the in-app virtual camera that Zoom /
/// Slack / Teams pick when the user selects "AV Pain Reliever" in
/// their own camera UI. A profile that names a camera should drive
/// both:
///
/// - `CameraController` so AVFoundation-modern apps follow the system
///   default.
/// - `VirtualCameraSourceController` so apps connected to the virtual
///   camera see frames from that same source.
///
/// `nil` injection (or omitting from `ProfileApplier`'s init) yields
/// a silent no-op — the v0.1.x release path that doesn't bundle the
/// Camera Extension simply doesn't pass one.
public protocol VirtualCameraSourceController {
    /// Switch the virtual camera's source to the AVFoundation device
    /// whose `localizedName` matches `named`. Idempotent — a re-set
    /// to the currently-active source returns `.ok` without churning
    /// the running capture session.
    func setSource(named: String) -> CameraApplyResult

    /// Localized name to use for the system-wide preferred camera
    /// (`AVCaptureDevice.userPreferredCamera`) when this controller
    /// is the active routing layer, or nil to fall through to the
    /// profile's literal camera name.
    ///
    /// When the host's virtual camera is enabled, the preferred
    /// camera should be the virtual camera itself — that's what
    /// AVFoundation-modern apps (FaceTime, Safari getUserMedia)
    /// pick up, so they route through the virtual camera the same
    /// way Zoom/Slack/Teams do once the user manually selects "AV
    /// Pain Reliever" in their picker. The profile still names the
    /// real source camera; `setSource(named:)` swaps the virtual
    /// camera's source to match.
    ///
    /// Returns nil when the controller is in any non-live state
    /// (off, activating, requires-relaunch) — `ProfileApplier`
    /// then sets the system preference to the profile's literal
    /// camera as it did pre-virtual-camera.
    var preferredCameraOverride: String? { get }
}

public extension VirtualCameraSourceController {
    /// Default for callers/mocks that don't model the override —
    /// preserves the historical "set system preferred to the
    /// profile's literal camera" behavior.
    var preferredCameraOverride: String? { nil }
}

/// Production `CameraController` backed by AVFoundation. Stateless;
/// every call goes through `CameraDiscovery.session()` for a fresh
/// device list (see `CameraDiscovery` for why fresh per call).
public struct AVFoundationCameraController: CameraController {
    public init() {}

    public func setPreferred(named: String) -> CameraApplyResult {
        let devices = CameraDiscovery.session().devices
        guard let device = devices.first(where: { $0.localizedName == named }) else {
            return .notFound
        }
        AVCaptureDevice.userPreferredCamera = device
        return .ok
    }

    public func availableCameras() -> [CameraSummary] {
        CameraDiscovery.session()
            .devices
            .map { CameraSummary(name: $0.localizedName) }
            .sorted { $0.name < $1.name }
    }

    public func currentPreferredName() -> String? {
        // Fall through three sources so the wizard always pre-selects
        // a meaningful camera (rather than "Don't change", which is
        // useful but rarely the right default):
        //
        // 1. userPreferredCamera — explicitly set by us or by the
        //    user via System Settings → Cameras. Often nil because
        //    most users have never touched it.
        // 2. systemPreferredCamera (macOS 14+) — what AVFoundation
        //    would currently pick. Falls back from userPreferred to
        //    the system's choice (typically the built-in webcam) if
        //    no user preference is set. Almost always non-nil when
        //    any camera is connected.
        // 3. First device in the discovery session — defensive
        //    last resort.
        if let user = AVCaptureDevice.userPreferredCamera {
            return user.localizedName
        }
        if let system = AVCaptureDevice.systemPreferredCamera {
            return system.localizedName
        }
        return CameraDiscovery.session().devices.first?.localizedName
    }
}
