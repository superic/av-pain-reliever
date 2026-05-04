import Foundation
import SystemExtensions

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
        NSLog("[AVPR] Submitted Camera Extension activation request")
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
        NSLog("[AVPR] Camera Extension needs user approval — open System Settings → Privacy & Security")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        NSLog("[AVPR] Camera Extension activation finished: result=\(result.rawValue)")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        NSLog("[AVPR] Camera Extension activation failed: \(error)")
    }
}
