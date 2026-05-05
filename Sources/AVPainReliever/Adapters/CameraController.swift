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

/// Abstraction over `AVCaptureDevice.userPreferredCamera` (macOS 14+
/// system-wide preferred camera). Production uses
/// `AVFoundationCameraController`; tests use a recording mock.
///
/// Scope and design notes:
///
/// - `userPreferredCamera` is the macOS-14+ system API for
///   "preferred default camera." AVFoundation-modern apps (FaceTime,
///   browser `getUserMedia`, native AVCapture clients) pick it up
///   automatically.
/// - Apps with their own camera-selection UI (Zoom, Slack, Teams,
///   OBS) maintain their OWN selection independently. The engine
///   intentionally does NOT try to drive those — no plist hacks, no
///   UI scripting. For users who need Zoom/Slack to follow the
///   profile too, V2's OBS support will let them route through OBS
///   Virtual Camera (configure OBS once with a per-scene camera,
///   point Zoom/Slack at OBS Virtual Camera once, OBS scene switch
///   handles the rest).
public protocol CameraController {
    /// Set the system's `userPreferredCamera` to the camera with the
    /// given `localizedName`. Returns `.notFound` if no such camera
    /// is currently visible.
    func setPreferred(named: String) -> CameraApplyResult

    /// Snapshot of available cameras, sorted by name. Used by the
    /// wizard UI to populate the camera picker.
    func availableCameras() -> [CameraSummary]

    /// Localized name of the camera currently set as
    /// `userPreferredCamera`, or nil if none is set / matches.
    func currentPreferredName() -> String?
}

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
}

/// Production `CameraController` backed by AVFoundation. Stateless —
/// every call constructs a fresh `DiscoverySession`. Sessions are
/// cheap (microseconds) and we want fresh results when the user
/// docks a Continuity Camera mid-wizard.
public struct AVFoundationCameraController: CameraController {
    public init() {}

    public func setPreferred(named: String) -> CameraApplyResult {
        let devices = Self.discoverySession().devices
        guard let device = devices.first(where: { $0.localizedName == named }) else {
            return .notFound
        }
        AVCaptureDevice.userPreferredCamera = device
        return .ok
    }

    public func availableCameras() -> [CameraSummary] {
        Self.discoverySession()
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
        return Self.discoverySession().devices.first?.localizedName
    }

    private static func discoverySession() -> AVCaptureDevice.DiscoverySession {
        // Include every camera type that surfaces on macOS 14+:
        //   - builtInWideAngleCamera: the Mac's own webcam
        //   - external: USB / Thunderbolt cameras (LG UltraFine,
        //     capture cards routed as cameras, etc.)
        //   - continuityCamera: iPhone-as-webcam
        //   - deskViewCamera: Apple's perspective-corrected
        //     ultra-wide variant
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
                .deskViewCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
    }
}
