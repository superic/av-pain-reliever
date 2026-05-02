import Foundation
import IOKit

/// USB device with its human-readable product + vendor names
/// attached. The resolver doesn't need names (matching is `(vid, pid)`
/// only), but the wizard UI does — when the user is picking which
/// devices belong to a location's fingerprint, "LG Electronics — USB
/// 2.1 Hub" is massively more useful than `vid=0x043e pid=0x9a61`,
/// and "LG UltraFine Display Camera" is unambiguous on its own.
public struct NamedUSBDevice: Hashable, Sendable, Identifiable {
    public let device: USBDevice
    /// USB Product Name string. `nil` when the device doesn't
    /// expose one — typically internal hub legs of multi-function
    /// devices like the LG UltraFine, which often have only a
    /// vendor name.
    public let name: String?
    /// USB Vendor Name string (e.g. "LG Electronics", "Apple Inc."),
    /// from IOKit's "USB Vendor Name" property. `nil` when the
    /// device doesn't expose one. Combined with `name` in the UI to
    /// disambiguate multi-function-device hub legs that share the
    /// same product label.
    public let vendorName: String?

    public init(device: USBDevice, name: String?, vendorName: String? = nil) {
        self.device = device
        self.name = name
        self.vendorName = vendorName
    }

    public var id: USBDevice { device }

    /// Human-friendly label for the wizard UI. Combines vendor +
    /// product name when both are available; falls back to whichever
    /// is set; falls back to `(unnamed device)` when neither is.
    public var displayName: String {
        switch (vendorName, name) {
        case let (.some(v), .some(n)): return "\(v) — \(n)"
        case (.some(let v), .none):    return v
        case (.none, .some(let n)):    return n
        case (.none, .none):           return "(unnamed device)"
        }
    }
}

/// Reads the set of currently-attached USB devices and notifies the
/// engine when that set changes. Production uses `IOKitUSBWatcher`;
/// tests inject a recording fake.
///
/// The engine re-enumerates fresh on every evaluation rather than
/// trusting an internal cache — USB events can race, duplicate, or be
/// dropped, so a confirmed snapshot at evaluation time is safer than
/// trying to maintain incremental state. This mirrors how the
/// Hammerspoon engine uses `hs.usb.attachedDevices()`.
public protocol USBWatcher {
    /// Fresh snapshot of the currently-attached USB devices. Cheap
    /// (microseconds on modern Macs); call as often as needed.
    func currentDevices() -> Set<USBDevice>

    /// Like `currentDevices()` but also returns each device's
    /// human-readable name. Used by the wizard UI when the user picks
    /// which currently-attached devices belong to a new location's
    /// fingerprint. Order is not guaranteed (IOKit's enumeration
    /// order isn't stable), so callers that need a deterministic
    /// list should sort by name or `(vid, pid)`.
    func currentDevicesNamed() -> [NamedUSBDevice]

    /// Begin observing USB add/remove events. `onChange` fires once
    /// per IOKit event burst on the main thread. Must be paired with a
    /// `stop()` call before the watcher is deallocated.
    ///
    /// Notifications generated during registration (the "initial state"
    /// pings IOKit emits when first-match is registered) are
    /// suppressed — `onChange` only fires for genuine changes after
    /// `start()` returns.
    func start(onChange: @escaping () -> Void)

    /// Stop observing. Idempotent; safe to call from `deinit`.
    func stop()
}

/// Production `USBWatcher` backed by IOKit. Lifted from
/// `prototypes/usb-watcher.swift` once that prototype proved the
/// notification-port + drained-iterator pattern works (see
/// `SWIFT_PORT.md` → "IOKit prototype findings").
///
/// Threading: the IOKit notification port is wired into the main run
/// loop, so `onChange` always fires on the main thread, matching the
/// rest of the engine's main-thread-only execution model.
public final class IOKitUSBWatcher: USBWatcher {
    /// Modern (XHCI) host-stack class. The legacy `IOUSBDevice` class
    /// returns nothing on Apple Silicon — confirmed during the IOKit
    /// prototype.
    private static let usbDeviceClass = "IOUSBHostDevice"

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0
    private var firstAddDrainDone = false
    private var firstRemoveDrainDone = false
    private var onChange: (() -> Void)?

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Snapshot

    public func currentDevices() -> Set<USBDevice> {
        guard let matching = IOServiceMatching(Self.usbDeviceClass) else {
            return []
        }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iter) }
        var devices: Set<USBDevice> = []
        Self.drain(iter) { entry in
            if let device = Self.deviceInfo(entry) {
                devices.insert(device)
            }
        }
        return devices
    }

    public func currentDevicesNamed() -> [NamedUSBDevice] {
        guard let matching = IOServiceMatching(Self.usbDeviceClass) else {
            return []
        }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iter) }
        var seen: Set<USBDevice> = []
        var named: [NamedUSBDevice] = []
        Self.drain(iter) { entry in
            guard let device = Self.deviceInfo(entry),
                  !seen.contains(device) else { return }
            seen.insert(device)
            named.append(NamedUSBDevice(
                device: device,
                name: Self.productName(entry),
                vendorName: Self.vendorName(entry)
            ))
        }
        // Sort for stable UI ordering (IOKit doesn't guarantee an
        // order, and the wizard list looks weird when devices shuffle
        // between renders). Use the same `displayName` the UI shows
        // so what the user sees is what drives the sort.
        return named.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Notifications

    public func start(onChange: @escaping () -> Void) {
        // Idempotent guard — calling start twice without an intervening
        // stop is a programmer error but shouldn't leak a notification
        // port.
        guard notifyPort == nil else { return }
        self.onChange = onChange

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            return
        }
        notifyPort = port

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        // Pass `self` to the C-style callbacks via the refCon
        // parameter. Unmanaged.passUnretained is safe here because the
        // notification port and iterators are owned by `self` — they
        // can't outlive it.
        let context = Unmanaged.passUnretained(self).toOpaque()

        let addedCallback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<IOKitUSBWatcher>.fromOpaque(refcon)
                .takeUnretainedValue()
                .handleAddedIterator(iterator)
        }

        let removedCallback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<IOKitUSBWatcher>.fromOpaque(refcon)
                .takeUnretainedValue()
                .handleRemovedIterator(iterator)
        }

        // IOServiceMatching consumes one CF reference per call site, so
        // build a fresh dict for each subscription. (Lesson from the
        // IOKit prototype.)
        if let added = IOServiceMatching(Self.usbDeviceClass) {
            IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, added,
                addedCallback, context, &addedIter
            )
        }
        if let removed = IOServiceMatching(Self.usbDeviceClass) {
            IOServiceAddMatchingNotification(
                port, kIOTerminatedNotification, removed,
                removedCallback, context, &removedIter
            )
        }

        // Manually drain the initial iterators to arm the
        // notifications. The first-match callback always fires once
        // synchronously here with all already-attached devices —
        // suppress those, since the caller already has the current set
        // via `currentDevices()`.
        handleAddedIterator(addedIter)
        handleRemovedIterator(removedIter)
    }

    public func stop() {
        guard let port = notifyPort else { return }
        IONotificationPortDestroy(port)
        notifyPort = nil
        addedIter = 0
        removedIter = 0
        firstAddDrainDone = false
        firstRemoveDrainDone = false
        onChange = nil
    }

    // MARK: - Iterator handlers

    private func handleAddedIterator(_ iter: io_iterator_t) {
        let suppress = !firstAddDrainDone
        var sawEvent = false
        Self.drain(iter) { _ in
            if !suppress { sawEvent = true }
        }
        firstAddDrainDone = true
        if sawEvent { onChange?() }
    }

    private func handleRemovedIterator(_ iter: io_iterator_t) {
        let suppress = !firstRemoveDrainDone
        var sawEvent = false
        Self.drain(iter) { _ in
            if !suppress { sawEvent = true }
        }
        firstRemoveDrainDone = true
        if sawEvent { onChange?() }
    }

    // MARK: - IOKit helpers

    /// Drain an iterator to exhaustion, releasing each entry.
    /// Non-negotiable per IOKit semantics — a partially-drained
    /// iterator stops re-arming the notification port.
    private static func drain(_ iter: io_iterator_t, body: (io_object_t) -> Void) {
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            body(entry)
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
    }

    private static func deviceInfo(_ entry: io_object_t) -> USBDevice? {
        guard let vid = intProperty(entry, "idVendor"),
              let pid = intProperty(entry, "idProduct") else {
            return nil
        }
        return USBDevice(vendorID: vid, productID: pid)
    }

    private static func productName(_ entry: io_object_t) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(
            entry, "USB Product Name" as CFString, kCFAllocatorDefault, 0
        ) else {
            return nil
        }
        return raw.takeRetainedValue() as? String
    }

    private static func vendorName(_ entry: io_object_t) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(
            entry, "USB Vendor Name" as CFString, kCFAllocatorDefault, 0
        ) else {
            return nil
        }
        return raw.takeRetainedValue() as? String
    }

    private static func intProperty(_ entry: io_object_t, _ key: String) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        ) else {
            return nil
        }
        return (raw.takeRetainedValue() as? NSNumber)?.intValue
    }
}
