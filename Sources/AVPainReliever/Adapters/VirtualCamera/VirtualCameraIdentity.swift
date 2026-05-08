import Foundation

/// Identity constants for the embedded AV Pain Reliever virtual
/// camera. The same values are hardcoded inside the Camera Extension
/// binary (`Sources/AVPainRelieverCameraExtension/`) — they have to
/// match by hand because the extension target is sandboxed and shares
/// no Swift module with the engine.
///
/// Lives in the engine library so the host-side capture adapters
/// (`CameraCaptureSession`, `CMIOSinkWriter`) can reference them
/// without depending on the app target. The app target's
/// `VirtualCameraActivator` re-exports them under its existing
/// `virtualCameraUID` / `virtualCameraDisplayName` names so callers
/// don't need to learn a new spelling.
public enum VirtualCameraIdentity {
    /// Stable UUID matching the extension's
    /// `CameraExtensionDeviceSource.deviceUUID`. The host uses this
    /// to find the virtual camera in the CMIO device list and to
    /// recognize its own output device when sorting cameras for the
    /// wizard.
    public static let deviceUID = "B45B7E4D-3F4E-4F4D-9C2A-1B2C3D4E5F60"

    /// Localized name the extension registers — also what
    /// AVFoundation reports for the virtual camera's
    /// `localizedName`. Used as the value of
    /// `preferredCameraOverride` so `ProfileApplier` can set the
    /// system-wide preferred camera to "AV Pain Reliever" when the
    /// virtual camera is live, mirroring what users set in Zoom.
    public static let displayName = "AV Pain Reliever"
}
