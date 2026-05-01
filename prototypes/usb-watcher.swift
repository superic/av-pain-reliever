// IOKit USB watcher proof-of-concept for the eventual Swift native app port.
//
// Goal: prove that IOKit USB watching produces output equivalent to
// Hammerspoon's hs.usb.watcher (the engine relies on hs.usb.attachedDevices()
// at startup + add/remove events to drive profile resolution).
//
// Run with:   swift prototypes/usb-watcher.swift
// Stop with:  Ctrl+C
//
// This is throwaway research code. The shape of the IOKit pieces (matching
// dict, notification port, drained iterators, run-loop integration) is what
// the real Swift app's USBWatcher.swift will be built around — see
// SWIFT_PORT.md → "IOKit prototype findings" for what we learned.

import Foundation
import IOKit

// stdout is block-buffered when piped (tail -f, redirection, etc.). For a
// long-running watcher we want each event to surface immediately.
setbuf(stdout, nil)

// IOKit USB property keys live in IOUSBLib.h as plain C #defines, which
// Swift's Clang importer does not surface as constants. Hard-code them.
private let usbDeviceClass = "IOUSBHostDevice" // modern (XHCI) host stack class
private let vendorIDKey = "idVendor"
private let productIDKey = "idProduct"
private let productNameKey = "USB Product Name" // a.k.a. kUSBProductString

private struct USBInfo {
    let vid: Int
    let pid: Int
    let name: String
}

// MARK: - IORegistry property helpers

private func intProperty(_ entry: io_object_t, _ key: String) -> Int? {
    guard let raw = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
        return nil
    }
    return (raw.takeRetainedValue() as? NSNumber)?.intValue
}

private func stringProperty(_ entry: io_object_t, _ key: String) -> String? {
    guard let raw = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
        return nil
    }
    return raw.takeRetainedValue() as? String
}

private func describe(_ entry: io_object_t) -> USBInfo {
    let vid = intProperty(entry, vendorIDKey) ?? 0
    let pid = intProperty(entry, productIDKey) ?? 0
    // Match the Hammerspoon engine: devices with no USB Product Name
    // string descriptor (LG UltraFine internal hub legs, etc.) render as
    // "?" rather than the IOKit registry entry name (which would just
    // be "IOUSBHostDevice", since unnamed entries inherit the class name).
    let name = stringProperty(entry, productNameKey) ?? "?"
    return USBInfo(vid: vid, pid: pid, name: name)
}

private func formatRow(prefix: String, _ info: USBInfo) -> String {
    // Match the Hammerspoon engine's snapshot format: lowercase 4-digit hex.
    return String(format: "%@vid=0x%04x pid=0x%04x  %@",
                  prefix as NSString,
                  CUnsignedInt(info.vid),
                  CUnsignedInt(info.pid),
                  info.name)
}

private func drain(_ iterator: io_iterator_t, body: (io_object_t) -> Void) {
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        body(entry)
        IOObjectRelease(entry)
        entry = IOIteratorNext(iterator)
    }
}

// MARK: - Snapshot of currently-attached devices

private func snapshot() {
    print("[snapshot]")
    guard let matching = IOServiceMatching(usbDeviceClass) else {
        FileHandle.standardError.write(Data("IOServiceMatching returned nil\n".utf8))
        return
    }
    var iter: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
    guard kr == KERN_SUCCESS else {
        FileHandle.standardError.write(Data("IOServiceGetMatchingServices failed: \(kr)\n".utf8))
        return
    }
    defer { IOObjectRelease(iter) }
    drain(iter) { entry in
        print(formatRow(prefix: "  ", describe(entry)))
    }
}

// MARK: - Live add/remove notifications
//
// IOServiceAddMatchingNotification's first-match callback fires once per
// already-present device on registration. We've already printed those as
// the snapshot, so the first drain of the added-iterator must be silent.
// Subsequent invocations of the callback represent real attach events.
//
// The terminated-iterator's first drain is normally empty (no devices have
// been removed since registration), but we still must drain it to arm the
// notification.
//
// IMPORTANT: do NOT release the iterator returned by
// IOServiceAddMatchingNotification — the notification port retains it.

private final class DrainState {
    var firstAddDone = false
    var firstRemoveDone = false
}

private let drainState = DrainState() // global → C-callable closures may reference it

private let addedCallback: IOServiceMatchingCallback = { _, iterator in
    let suppress = !drainState.firstAddDone
    drain(iterator) { entry in
        if !suppress {
            print(formatRow(prefix: "[add]    ", describe(entry)))
        }
    }
    drainState.firstAddDone = true
}

private let removedCallback: IOServiceMatchingCallback = { _, iterator in
    let suppress = !drainState.firstRemoveDone
    drain(iterator) { entry in
        if !suppress {
            print(formatRow(prefix: "[remove] ", describe(entry)))
        }
    }
    drainState.firstRemoveDone = true
}

// MARK: - Wire it up

snapshot()

guard let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else {
    FileHandle.standardError.write(Data("IONotificationPortCreate failed\n".utf8))
    exit(1)
}
let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

func subscribe(_ type: String, _ callback: IOServiceMatchingCallback) -> io_iterator_t {
    guard let matching = IOServiceMatching(usbDeviceClass) else {
        FileHandle.standardError.write(Data("IOServiceMatching returned nil\n".utf8))
        exit(1)
    }
    var iter: io_iterator_t = 0
    let kr = IOServiceAddMatchingNotification(notifyPort, type, matching, callback, nil, &iter)
    guard kr == KERN_SUCCESS else {
        FileHandle.standardError.write(Data("IOServiceAddMatchingNotification(\(type)) failed: \(kr)\n".utf8))
        exit(1)
    }
    return iter
}

let addedIter = subscribe(kIOFirstMatchNotification, addedCallback)
addedCallback(nil, addedIter) // drain the initial set + arm the notification

let removedIter = subscribe(kIOTerminatedNotification, removedCallback)
removedCallback(nil, removedIter) // drain (likely empty) + arm

// SIGINT terminates the process; IOKit cleanup on exit is implicit and
// fine for a prototype.
RunLoop.main.run()
