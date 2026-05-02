// CoreAudio audio-device proof-of-concept for the eventual Swift native
// app port.
//
// Goal: prove we can do everything `hs.audiodevice` does for us in the
// engine — enumerate input/output devices, read the current system
// defaults, and switch defaults by name. This de-risks the second
// framework dependency (after IOKit USB) before we commit to building
// `AudioController.swift` for real.
//
// Run with:   swift prototypes/audio-defaults.swift
//
// Behavior (read-only — does NOT change your defaults):
//   1. Print a snapshot of every audio device with its in=/out= capability,
//      matching the engine's `--- audio devices ---` log format.
//   2. Print the current default input + output device names.
//   3. Verify the set-default codepath by setting each default to its
//      *current* value (idempotent no-op). If the OSStatus is `noErr`,
//      the production AudioController can use the same call to actually
//      switch devices.
//
// This is throwaway research code; the production version belongs in
// AudioController.swift, probably wrapping SimplyCoreAudio per the
// SWIFT_PORT.md plan.

import Foundation
import CoreAudio

setbuf(stdout, nil)

// MARK: - Property-address helpers
//
// Every CoreAudio call wants an AudioObjectPropertyAddress. Building
// these inline at every call site is noisy; factor it out.

private func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    return AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

// MARK: - Generic property reads

private func propertyDataSize(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> UInt32 {
    var addr = address(selector, scope: scope)
    var size: UInt32 = 0
    let kr = AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size)
    return kr == noErr ? size : 0
}

// MARK: - Device queries

private func allDeviceIDs() -> [AudioDeviceID] {
    let size = propertyDataSize(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    var addr = address(kAudioHardwarePropertyDevices)
    var resultSize = size
    let kr = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addr, 0, nil, &resultSize, &ids
    )
    return kr == noErr ? ids : []
}

private func deviceName(_ id: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
    let kr = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    guard kr == noErr, let cf = name?.takeRetainedValue() else { return "?" }
    return cf as String
}

private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    return propertyDataSize(id, kAudioDevicePropertyStreams, scope: scope) > 0
}

// MARK: - Default-device read/write

private enum DefaultRole {
    case input
    case output

    var selector: AudioObjectPropertySelector {
        switch self {
        case .input:  return kAudioHardwarePropertyDefaultInputDevice
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

private func defaultDevice(_ role: DefaultRole) -> AudioDeviceID? {
    var addr = address(role.selector)
    var device: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let kr = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addr, 0, nil, &size, &device
    )
    return kr == noErr ? device : nil
}

private func setDefaultDevice(_ id: AudioDeviceID, role: DefaultRole) -> OSStatus {
    var addr = address(role.selector)
    var device = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addr, 0, nil, size, &device
    )
}

// MARK: - Output

print("[snapshot]")
let ids = allDeviceIDs()
for id in ids {
    let name = deviceName(id)
    let isInput = hasStreams(id, scope: kAudioDevicePropertyScopeInput)
    let isOutput = hasStreams(id, scope: kAudioDevicePropertyScopeOutput)
    // Match the engine's `--- audio devices ---` log format exactly:
    //   "<name>"  in=<bool> out=<bool>
    print(String(format: "  \"%@\"  in=%@ out=%@",
                 name as NSString,
                 isInput ? "true" : "false",
                 isOutput ? "true" : "false"))
}

print("[defaults]")
if let inputID = defaultDevice(.input) {
    print("  input:  \(deviceName(inputID))")
} else {
    print("  input:  <none>")
}
if let outputID = defaultDevice(.output) {
    print("  output: \(deviceName(outputID))")
} else {
    print("  output: <none>")
}

// Verify the set-default codepath without changing user state: set each
// default to its current value (idempotent). If OSStatus is `noErr` we
// know the production AudioController can use the same API to actually
// switch devices when a profile applies.
print("[verify set-default]")
for role in [DefaultRole.input, .output] {
    let label = role == .input ? "input " : "output"
    guard let current = defaultDevice(role) else {
        print("  \(label): skipped (no current default)")
        continue
    }
    let kr = setDefaultDevice(current, role: role)
    if kr == noErr {
        print("  \(label): ok (set to current → \(deviceName(current)))")
    } else {
        print("  \(label): FAILED OSStatus=\(kr)")
    }
}
