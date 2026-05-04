import Foundation
import CoreMediaIO
import os.log

private let mainLogger = Logger(
    subsystem: "com.ericwillis.avpainreliever.CameraExtension",
    category: "Main"
)

mainLogger.info("Camera Extension process starting up")

// Camera Extension entry point. Lives in its own process — this
// binary is wrapped as `.systemextension` by
// scripts/make-app-with-virtual-camera.sh and embedded inside
// AVPainReliever.app at Contents/Library/SystemExtensions/.
//
// macOS launches this on demand when the host app activates the
// extension via OSSystemExtensionRequest, then keeps it running as
// long as any AVCapture client (Zoom, FaceTime, Slack, ...) has the
// "AV Pain Reliever" camera selected, OR while the host app has
// the sink stream open and is pushing frames in.
//
// Architecture: the extension owns a CMIO device with two streams.
// The .source stream is what AVCapture clients read from. The
// .sink stream is what the host app writes frames into via
// CMSimpleQueueEnqueue. The device source pumps frames sink →
// source via `consumeSampleBuffer`. macOS's CMIO subsystem passes
// IOSurfaces between processes for free, no XPC involved.

let providerSource = CameraExtensionProviderSource(clientQueue: nil)
mainLogger.info("Provider source initialised, calling CMIOExtensionProvider.startService")
CMIOExtensionProvider.startService(provider: providerSource.provider)
mainLogger.info("Service started, entering CFRunLoopRun")
CFRunLoopRun()
