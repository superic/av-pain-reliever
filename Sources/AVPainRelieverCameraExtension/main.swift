import Foundation
import CoreMediaIO

// Camera Extension entry point. Lives in its own process — this
// binary is wrapped as `.systemextension` by
// scripts/make-app-with-virtual-camera.sh and embedded inside
// AVPainReliever.app at Contents/Library/SystemExtensions/.
//
// macOS launches this on demand when the host app activates the
// extension via OSSystemExtensionRequest, then keeps it running as
// long as any AVCapture client (Zoom, FaceTime, Slack, ...) has the
// "AV Pain Reliever" camera selected.
//
// M1 scope: vend a black 1280x720 frame at 30 fps. No source-camera
// switching, no XPC. Just enough to prove the activation/embedding/
// signing plumbing end-to-end.

let providerSource = CameraExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
