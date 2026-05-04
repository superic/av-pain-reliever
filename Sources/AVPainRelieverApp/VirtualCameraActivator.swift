import Foundation
import SystemExtensions
import os.log

private let logger = Logger(
    subsystem: "com.ericwillis.avpainreliever",
    category: "Activator"
)

/// M1 plumbing: triggers `OSSystemExtensionRequest` activation for
/// the embedded Camera Extension when the env var
/// `AVPR_ACTIVATE_VIRTUAL_CAMERA=1` is set at launch.
///
/// Why an env var instead of a Settings toggle: M1 is just proving
/// the activation/embedding/signing plumbing. A real opt-in toggle
/// in Settings lands in M4. The env-var path stays in the codebase
/// for the lifetime of the feature branch as a debug affordance —
/// hidden from regular users, useful for re-activating after a
/// `systemextensionsctl uninstall`.
///
/// Requires the `com.apple.developer.system-extension.install`
/// entitlement on the host app. v0.1.x builds don't have it; calls
/// from those builds will fail with an authorization error, which
/// is the intended no-op.
final class VirtualCameraActivator: NSObject, OSSystemExtensionRequestDelegate {
    static let extensionBundleID = "com.ericwillis.avpainreliever.CameraExtension"
    static let envVar = "AVPR_ACTIVATE_VIRTUAL_CAMERA"

    private static var retained: VirtualCameraActivator?
    private static var sinkWriter: CMIOSinkWriter?
    private static var captureSession: CameraCaptureSession?

    /// Stable UUID matching the extension's
    /// `CameraExtensionDeviceSource.deviceUUID`. The host uses this
    /// to find the virtual camera in the CMIO device list.
    private static let virtualCameraUID = "B45B7E4D-3F4E-4F4D-9C2A-1B2C3D4E5F60"

    static func activateIfRequested() {
        guard ProcessInfo.processInfo.environment[envVar] == "1" else { return }
        let activator = VirtualCameraActivator()
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = activator
        OSSystemExtensionManager.shared.submitRequest(request)
        // Retain across the async lifecycle. App-lifetime retention
        // is fine — there's at most one of these per launch.
        retained = activator
        logger.info("Submitted Camera Extension activation request")

        // Start the host-side capture pipeline. The CMIOSinkWriter
        // lazily finds the device + sink stream on first enqueue,
        // so even on a fresh activation it starts producing frames
        // as soon as the extension is enabled.
        startCapturePipeline()
    }

    private static func startCapturePipeline() {
        let writer = CMIOSinkWriter(
            deviceUID: virtualCameraUID,
            width: 1280,
            height: 720
        )
        let session = CameraCaptureSession(sink: writer)
        session.start()
        sinkWriter = writer
        captureSession = session
        logger.info("Started host-side capture + CMIO sink writer")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Always replace. Sparkle-installed upgrades will hit this
        // path for every v0.2.x → v0.2.y bump.
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("Camera Extension needs user approval — open System Settings → Login Items & Extensions → Camera Extensions")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        logger.info("Camera Extension activation finished: result=\(result.rawValue, privacy: .public)")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        logger.error("Camera Extension activation failed: \(error.localizedDescription, privacy: .public)")
    }
}
