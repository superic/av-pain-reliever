import Foundation
@testable import AVPainReliever

/// In-memory `USBWatcher` for engine tests. The current attached set
/// is a settable property; `triggerChange()` invokes the registered
/// `onChange` closure, simulating a USB event without involving IOKit.
final class RecordingUSBWatcher: USBWatcher {
    var devices: Set<USBDevice> = []
    /// Optional override for `currentDevicesNamed`. When unset, the
    /// fake derives a list from `devices` with `name = nil`.
    var namedDevices: [NamedUSBDevice]?
    private var onChange: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    var isStarted: Bool { onChange != nil }

    func currentDevices() -> Set<USBDevice> { devices }

    func currentDevicesNamed() -> [NamedUSBDevice] {
        if let namedDevices { return namedDevices }
        return devices.map { NamedUSBDevice(device: $0, name: nil) }
    }

    func start(onChange: @escaping () -> Void) {
        // Match production: idempotent — second start without intervening
        // stop is a no-op.
        guard self.onChange == nil else { return }
        self.onChange = onChange
        startCount += 1
    }

    func stop() {
        guard onChange != nil else { return }
        onChange = nil
        stopCount += 1
    }

    /// Test helper — fire the registered onChange closure as if IOKit
    /// delivered a USB add/remove event.
    func triggerChange() {
        onChange?()
    }
}
